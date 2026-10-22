import tempfile
import unittest
from pathlib import Path

from director.campaign import read_log, session_digest
from director.catalogue import Decision
from director.decider import Director
from director.pacing import has_news
from tests.test_decider import STATE, ScriptedBackend

KILLS = [3, "kills", "The rebels killed 4 occupants"]
OUTCOME = [4, "outcome", "Your spawn_patrol (occupants) against Alpha 1-1, 5 min ago: wiped out, all 5 killed"]


class FeedbackTests(unittest.TestCase):
    def setUp(self) -> None:
        self.log_dir = Path(tempfile.mkdtemp())

    def test_news(self) -> None:
        self.assertFalse(has_news(STATE))
        self.assertFalse(has_news({**STATE, "events": [KILLS]}))
        self.assertTrue(has_news({**STATE, "events": [KILLS, OUTCOME]}))

    def test_news_is_never_skipped_but_tallies_wait_for_the_next_look(self) -> None:
        backend = ScriptedBackend(Decision.wait("a"), Decision.wait("b"), Decision.wait("c"))
        director = Director(backend, self.log_dir, max_skip=300)
        director.decide(STATE)
        skipped = director.decide({**STATE, "events": [KILLS]})
        self.assertTrue(skipped.reason.startswith("skipped"))
        director.decide({**STATE, "events": [OUTCOME]})
        self.assertEqual(len(backend.messages), 2)
        # The tally from the skipped state reaches Claude with the next state it sees.
        self.assertIn("The rebels killed 4 occupants", backend.messages[1])
        self.assertIn("wiped out, all 5 killed", backend.messages[1])

    def test_digest_lists_each_event_once(self) -> None:
        backend = ScriptedBackend(Decision.wait("a"), Decision.wait("b"))
        director = Director(backend, self.log_dir, max_skip=300)
        director.decide({**STATE, "time": 60})
        director.decide({**STATE, "time": 180, "events": [KILLS]})  # skipped
        director.decide({**STATE, "time": 240, "events": [OUTCOME]})
        digest = session_digest(read_log(director.log_path))
        self.assertEqual(digest.count("The rebels killed 4 occupants"), 1)
        self.assertIn("- 0:03 kills: The rebels killed 4 occupants", digest)
        self.assertIn("- 0:04 outcome: Your spawn_patrol (occupants) against Alpha 1-1", digest)


if __name__ == "__main__":
    unittest.main()
