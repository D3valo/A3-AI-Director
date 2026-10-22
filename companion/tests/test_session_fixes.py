"""Fixes from the first in-game test session (2026-10-22)."""
import json
import tempfile
import unittest
from pathlib import Path

from director.catalogue import Budget, Decision, check
from director.decider import Director
from tests.test_decider import STATE, ScriptedBackend

ANTISTASI = {**STATE, "antistasi": {"war_level": 1, "occupants_attack_resources": -1600, "active_missions": []}}


def act(action: str, **fields) -> Decision:
    return Decision.wait("test").model_copy(update={"action": action, **fields})


def current_state(message: str) -> dict:
    return json.loads(message.split("Current state:\n", 1)[1])


class SessionFixTests(unittest.TestCase):
    def setUp(self) -> None:
        self.log_dir = Path(tempfile.mkdtemp())

    def test_cooldowns_are_listed_for_claude(self) -> None:
        backend = ScriptedBackend(act("narrate", message="Static."), Decision.wait("a"))
        director = Director(backend, self.log_dir)
        director.decide(STATE)
        director.decide(STATE)
        self.assertIn("Actions on cooldown (minutes left); every other action is available now:\nnone",
                      backend.messages[0])
        self.assertIn("\nnarrate (2)\n", backend.messages[1])

    def test_claude_sees_minutes(self) -> None:
        backend = ScriptedBackend(Decision.wait("a"), Decision.wait("b"))
        director = Director(backend, self.log_dir)
        director.decide({**STATE, "time": 734})
        director.decide({**STATE, "time": 824})
        state = current_state(backend.messages[1])
        self.assertNotIn("time", state)
        self.assertEqual(state["minute"], 14)
        self.assertIn('"minute": 12', backend.messages[1])  # the recent decision

    def test_request_news(self) -> None:
        on_cooldown = act("narrate", message="Static.")
        backend = ScriptedBackend(on_cooldown, act("narrate", message="Again.", request_done=False),
                                  Decision.wait("not now"), act("supply_drop", target_player="Alpha 1-1", request_done=True))
        director = Director(backend, self.log_dir)
        self.assertEqual(director.reply(STATE)["request_news"], "")
        first = director.reply({**STATE, "request": "a line of atmosphere"})["request_news"]
        self.assertTrue(first.startswith("waiting: narrate is not possible yet (rejected narrate: on cooldown"), first)
        self.assertEqual(director.reply(STATE)["request_news"], "")  # nothing new to say
        done = director.reply(ANTISTASI)["request_news"]
        self.assertEqual(done, "the director chose supply_drop: test")

    def test_declined_request(self) -> None:
        backend = ScriptedBackend(act("wait", reason="No action can raise the war level.", request_done=True))
        news = Director(backend, self.log_dir).reply({**STATE, "request": "raise the war level"})["request_news"]
        self.assertEqual(news, "can't be done: No action can raise the war level.")

    def test_host_request_may_push_an_offensive_into_debt(self) -> None:
        offensive = act("launch_offensive")
        self.assertEqual(check(offensive, ANTISTASI, Budget()).action, "wait")
        self.assertEqual(check(offensive, ANTISTASI, Budget(), host_request=True).action, "launch_offensive")

    def test_informant_shares_the_intel_cooldown(self) -> None:
        budget = Budget()
        check(act("informant", target_player="Alpha 1-1"), STATE, budget)
        self.assertEqual(check(act("reveal_enemies", target_player="Alpha 1-1"), STATE, budget).action, "wait")

    def test_self_test_always_reaches_claude(self) -> None:
        backend = ScriptedBackend(Decision.wait("a"), Decision.wait("b"))
        director = Director(backend, self.log_dir, max_skip=300)
        director.decide(STATE)
        director.decide({**STATE, "self_test": True})
        self.assertEqual(len(backend.messages), 2)
        self.assertNotIn("self_test", current_state(backend.messages[1]))


if __name__ == "__main__":
    unittest.main()
