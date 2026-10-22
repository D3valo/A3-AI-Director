import tempfile
import unittest
from pathlib import Path

from director.campaign import Campaign, session_digest, session_name
from director.catalogue import Decision
from director.decider import Director
from tests.test_decider import STATE, ScriptedBackend, spawn


class CampaignTests(unittest.TestCase):
    def setUp(self) -> None:
        self.campaign = Campaign(Path(tempfile.mkdtemp()), "test")

    def play_session(self) -> Path:
        """Three waits, a host request, then a patrol; returns the session's log."""
        backend = ScriptedBackend(Decision.wait("quiet"), Decision.wait("quiet"), Decision.wait("quiet"), spawn(True))
        director = Director(backend, self.campaign.logs_dir)
        for i in range(3):
            director.decide({**STATE, "time": 90 * (i + 1)})
        director.decide({**STATE, "time": 3700, "request": "send a squad"})
        return director.log_path

    def test_digest_collapses_waits_and_lists_actions(self) -> None:
        from director.campaign import read_log

        digest = session_digest(read_log(self.play_session()))
        self.assertIn("- (3 waits)", digest)
        self.assertIn("- 1:01 host request: send a squad", digest)
        self.assertIn("- 1:01 spawn_patrol (target_player=Alpha 1-1, strength=squad): asked", digest)

    def test_write_report_saves_report_and_story(self) -> None:
        log_path = self.play_session()
        backend = ScriptedBackend({"report": "# The Long Wait\n\nNothing much.", "story": "The cell waited."})
        report = self.campaign.write_report(log_path, backend)
        self.assertEqual(report.read_text(encoding="utf-8"), "# The Long Wait\n\nNothing much.\n")
        self.assertEqual(self.campaign.story(), "The cell waited.")
        self.assertIn("This is the first session.", backend.messages[0])

    def test_failed_report_keeps_old_story(self) -> None:
        self.campaign.story_path.write_text("Old story.", encoding="utf-8")
        self.assertIsNone(self.campaign.write_report(self.play_session(), ScriptedBackend(None)))
        self.assertEqual(self.campaign.story(), "Old story.")

    def test_latest_log(self) -> None:
        self.assertIsNone(self.campaign.latest_log())
        log_path = self.play_session()
        self.assertEqual(self.campaign.latest_log(), log_path)

    def test_session_name(self) -> None:
        self.assertEqual(session_name(Path("decisions-20261022-182648.jsonl")), "2026-10-22 18:26")


if __name__ == "__main__":
    unittest.main()
