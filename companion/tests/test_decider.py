import json
import tempfile
import unittest
from pathlib import Path

from director.backends import Answer
from director.catalogue import Decision
from director.decider import Director

STATE = {"time": 100, "players": [{"name": "Alpha 1-1"}]}


class ScriptedBackend:
    """Returns the queued answers in order and records the messages it was asked."""

    name = "scripted"

    def __init__(self, *answers: Decision | dict | None) -> None:
        self.answers = list(answers)
        self.messages: list[str] = []
        self.systems: list[list[str]] = []

    def structured(
        self, system: list[str], user: str, schema: dict, effort: str, timeout: float, cache: bool = True
    ) -> Answer:
        self.systems.append(system)
        self.messages.append(user)
        answer = self.answers.pop(0)
        if answer is None:
            return Answer(None, error="scripted failure")
        return Answer(answer.model_dump() if isinstance(answer, Decision) else answer)


def spawn(request_done: bool) -> Decision:
    return Decision.wait("asked").model_copy(update={
        "action": "spawn_patrol", "target_player": "Alpha 1-1", "strength": "squad", "request_done": request_done,
    })


def section(message: str, heading: str) -> str | None:
    lines = message.splitlines()
    if heading not in lines:
        return None
    return lines[lines.index(heading) + 1]


def pending_request(message: str) -> object:
    value = section(message, "Pending player request:")
    return None if value == "none" else json.loads(value)


class DirectorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.log_dir = Path(tempfile.mkdtemp())

    def test_request_kept_until_done(self) -> None:
        backend = ScriptedBackend(Decision.wait("not yet"), spawn(request_done=True), Decision.wait("quiet"))
        director = Director(backend, self.log_dir)
        director.decide({**STATE, "request": "send a squad at us"})
        director.decide(STATE)
        director.decide(STATE)
        self.assertEqual(pending_request(backend.messages[0])["text"], "send a squad at us")
        self.assertEqual(pending_request(backend.messages[1])["text"], "send a squad at us")
        self.assertIsNone(pending_request(backend.messages[2]))

    def test_request_not_in_state_sent_to_claude(self) -> None:
        backend = ScriptedBackend(Decision.wait("ok"))
        Director(backend, self.log_dir).decide({**STATE, "request": "hello"})
        state = json.loads(backend.messages[0].split("Current state:\n", 1)[1])
        self.assertNotIn("request", state)

    def test_rejected_action_keeps_request(self) -> None:
        # The second spawn is on cooldown, so it becomes a wait and the request stays pending.
        backend = ScriptedBackend(spawn(request_done=False), spawn(request_done=True), Decision.wait("quiet"))
        director = Director(backend, self.log_dir)
        director.decide(STATE)
        director.decide({**STATE, "request": "another squad"})
        director.decide(STATE)
        self.assertEqual(pending_request(backend.messages[2])["text"], "another squad")

    def test_new_request_replaces_old(self) -> None:
        backend = ScriptedBackend(Decision.wait("a"), Decision.wait("b"))
        director = Director(backend, self.log_dir)
        director.decide({**STATE, "request": "first"})
        director.decide({**STATE, "request": "second"})
        self.assertEqual(pending_request(backend.messages[1])["text"], "second")

    def test_failed_or_malformed_answer_waits(self) -> None:
        director = Director(ScriptedBackend(None, {"action": "nuke"}), self.log_dir)
        self.assertEqual(director.decide(STATE).action, "wait")
        self.assertEqual(director.decide(STATE).action, "wait")

    def test_story_is_a_cached_system_block(self) -> None:
        backend = ScriptedBackend(Decision.wait("a"))
        Director(backend, self.log_dir, story="The cell hit a convoy at Kavala.").decide(STATE)
        self.assertEqual(len(backend.systems[0]), 2)
        self.assertIn("The cell hit a convoy at Kavala.", backend.systems[0][1])
        self.assertNotIn("Kavala", backend.messages[0])

    def test_no_story_section_without_story(self) -> None:
        backend = ScriptedBackend(Decision.wait("a"))
        Director(backend, self.log_dir).decide(STATE)
        self.assertEqual(len(backend.systems[0]), 1)


if __name__ == "__main__":
    unittest.main()
