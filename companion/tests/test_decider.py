import json
import tempfile
import unittest
from pathlib import Path

from director.catalogue import Decision
from director.decider import Director

STATE = {"time": 100, "players": [{"name": "Alpha 1-1"}]}


class ScriptedBackend:
    """Returns the queued decisions in order and records the messages it was asked."""

    name = "scripted"

    def __init__(self, *decisions: Decision) -> None:
        self.decisions = list(decisions)
        self.messages: list[str] = []

    def ask(self, user: str) -> tuple[Decision, dict | None]:
        self.messages.append(user)
        return self.decisions.pop(0), None


def spawn(request_done: bool) -> Decision:
    return Decision.wait("asked").model_copy(update={
        "action": "spawn_patrol", "target_player": "Alpha 1-1", "strength": "squad", "request_done": request_done,
    })


def pending_request(message: str) -> object:
    lines = message.splitlines()
    value = lines[lines.index("Pending player request:") + 1]
    return None if value == "none" else json.loads(value)


class RequestTests(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
