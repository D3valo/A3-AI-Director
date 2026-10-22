import tempfile
import unittest
from pathlib import Path

from director.campaign import read_log, session_digest
from director.catalogue import Decision
from director.decider import Director
from tests.test_decider import STATE, ScriptedBackend

PLAN = {
    "title": "The Hunt",
    "premise": "The occupiers want the cell that hit their convoy.",
    "beats": [
        {"goal": "A recon flight finds them", "suggested_actions": "heli_recon", "not_before_minute": 0},
        {"goal": "A patrol closes in", "suggested_actions": "spawn_patrol", "not_before_minute": 5},
        {"goal": "The hunters' officer shows himself", "suggested_actions": "enemy_vip", "not_before_minute": 15},
    ],
    "ending": "The cell kills the officer or slips away.",
}


def beat_done(reason: str = "delivered") -> Decision:
    return Decision.wait(reason).model_copy(update={"arc_beat_done": True})


def section(message: str, heading: str) -> str:
    lines = message.splitlines()
    return lines[lines.index(heading) + 1]


class ArcTests(unittest.TestCase):
    def setUp(self) -> None:
        folder = Path(tempfile.mkdtemp())
        self.log_dir = folder / "logs"
        self.arc_path = folder / "arc.json"

    def director(self, backend: ScriptedBackend, **options) -> Director:
        return Director(backend, self.log_dir, arc_path=self.arc_path, **options)

    def test_start_follow_and_complete(self) -> None:
        backend = ScriptedBackend(PLAN, Decision.wait("setting up"), beat_done(), beat_done(), beat_done("caught"))
        director = self.director(backend)
        reply = director.reply({**STATE, "arc_request": {"text": "a manhunt", "stop": False}})
        self.assertEqual(reply["arc"], {"title": "The Hunt", "beat": 1, "beats": 3, "event": "started"})
        self.assertTrue(self.arc_path.exists())
        self.assertIn("[CURRENT] A recon flight finds them", backend.messages[1])

        self.assertEqual(director.reply(STATE)["arc"]["beat"], 2)
        director.reply(STATE)
        # Each message is written before its decision moves the arc on.
        self.assertIn("[CURRENT] A patrol closes in", backend.messages[3])
        last = director.reply(STATE)
        self.assertEqual(last["arc"], {"title": "The Hunt", "beat": 3, "beats": 3, "event": "completed"})
        self.assertFalse(self.arc_path.exists())
        self.assertIsNone(director.arc)

    def test_stop(self) -> None:
        director = self.director(ScriptedBackend(PLAN, Decision.wait("a"), Decision.wait("b")))
        director.reply({**STATE, "arc_request": {"text": "", "stop": False}})
        reply = director.reply({**STATE, "arc_request": {"stop": True}})
        self.assertEqual(reply["arc"]["event"], "stopped")
        self.assertEqual(reply["arc"]["title"], "The Hunt")
        self.assertFalse(self.arc_path.exists())

    def test_failed_plan(self) -> None:
        director = self.director(ScriptedBackend(None, Decision.wait("a")))
        reply = director.reply({**STATE, "arc_request": {"text": "x", "stop": False}})
        self.assertEqual(reply["arc"]["event"], "failed")
        self.assertIsNone(director.arc)

    def test_malformed_plan(self) -> None:
        director = self.director(ScriptedBackend({**PLAN, "beats": []}, Decision.wait("a")))
        self.assertEqual(director.reply({**STATE, "arc_request": {"text": "x"}})["arc"]["event"], "failed")

    def test_survives_a_restart(self) -> None:
        self.director(ScriptedBackend(PLAN, beat_done())).reply({**STATE, "arc_request": {"text": "x"}})
        backend = ScriptedBackend(Decision.wait("a"))
        restarted = self.director(backend)
        self.assertEqual(restarted.arc.title, "The Hunt")
        restarted.reply(STATE)
        self.assertEqual(section(backend.messages[0], "Active story arc:"), '"The Hunt", started 0 min ago (x).')
        self.assertIn("[CURRENT] A patrol closes in", backend.messages[0])

    def test_an_active_arc_is_never_skipped(self) -> None:
        backend = ScriptedBackend(PLAN, Decision.wait("a"), Decision.wait("b"))
        director = self.director(backend, max_skip=300)
        director.reply({**STATE, "arc_request": {"text": "x"}})
        director.reply(STATE)
        self.assertEqual(len(backend.messages), 3)  # plan + two decisions, none skipped

    def test_digest(self) -> None:
        director = self.director(ScriptedBackend(PLAN, Decision.wait("a"), beat_done("recon flew"), beat_done(),
                                                 beat_done()))
        director.reply({**STATE, "time": 60, "arc_request": {"text": "a manhunt"}})
        for minutes in (2, 3, 4):
            director.reply({**STATE, "time": 60 * minutes})
        digest = session_digest(read_log(director.log_path))
        self.assertIn('- 0:01 story arc started: "The Hunt" (3 beats). The occupiers want the cell', digest)
        self.assertIn('- 0:02 arc "The Hunt": beat 1 of 3 done', digest)
        self.assertIn('- 0:04 story arc completed: "The Hunt"', digest)


if __name__ == "__main__":
    unittest.main()
