import copy
import tempfile
import unittest
from pathlib import Path

from director.catalogue import Decision
from director.decider import Director
from director.pacing import Pacer, fingerprint
from tests.test_decider import ScriptedBackend

STATE = {
    "time": 100,
    "daytime": 12.0,
    "players": [{"name": "Alpha 1-1", "alive": True, "damage": 0, "nearby_enemies_1km": 2, "group_size": 4,
                 "in_vehicle": False, "pos": [1000, 1000, 0]}],
    "antistasi": {"war_level": 2, "aggression_occupants": 30, "active_missions": [], "big_attack_in_progress": False},
}


def changed(**player) -> dict:
    state = copy.deepcopy(STATE)
    state["players"][0].update(player)
    return state


class FakeClock:
    def __init__(self) -> None:
        self.now = 0.0

    def __call__(self) -> float:
        return self.now


class FingerprintTests(unittest.TestCase):
    def test_small_changes_are_the_same(self) -> None:
        self.assertEqual(fingerprint(STATE), fingerprint(changed(damage=0.05, nearby_enemies_1km=3, pos=[1100, 1050, 0])))
        self.assertEqual(fingerprint(STATE), fingerprint({**STATE, "time": 400, "daytime": 13.5}))

    def test_important_changes_differ(self) -> None:
        for player in ({"alive": False}, {"damage": 0.5}, {"nearby_enemies_1km": 9}, {"in_vehicle": True},
                       {"pos": [1600, 1000, 0]}, {"group_size": 2}):
            self.assertNotEqual(fingerprint(STATE), fingerprint(changed(**player)), player)
        self.assertNotEqual(fingerprint(STATE), fingerprint({**STATE, "daytime": 21.0}))
        missions = {**STATE, "antistasi": {**STATE["antistasi"], "active_missions": ["CONVOY"]}}
        self.assertNotEqual(fingerprint(STATE), fingerprint(missions))


class PacerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.clock = FakeClock()
        self.pacer = Pacer(300, self.clock)

    def test_skips_unchanged_until_max_skip(self) -> None:
        self.assertFalse(self.pacer.should_skip(STATE, has_request=False))  # never asked yet
        self.pacer.asked(STATE)
        self.clock.now = 299
        self.assertTrue(self.pacer.should_skip(STATE, has_request=False))
        self.clock.now = 300
        self.assertFalse(self.pacer.should_skip(STATE, has_request=False))

    def test_change_or_request_asks(self) -> None:
        self.pacer.asked(STATE)
        self.assertFalse(self.pacer.should_skip(changed(alive=False), has_request=False))
        self.assertFalse(self.pacer.should_skip(STATE, has_request=True))

    def test_zero_always_asks(self) -> None:
        pacer = Pacer(0, self.clock)
        pacer.asked(STATE)
        self.assertFalse(pacer.should_skip(STATE, has_request=False))


class DirectorPacingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.log_dir = Path(tempfile.mkdtemp())

    def test_unchanged_state_skips_claude(self) -> None:
        backend = ScriptedBackend(Decision.wait("quiet"), Decision.wait("still quiet"))
        director = Director(backend, self.log_dir, max_skip=300)
        director.decide(STATE)
        skipped = director.decide(STATE)
        self.assertTrue(skipped.reason.startswith("skipped"))
        self.assertEqual(len(backend.messages), 1)
        director.decide(changed(nearby_enemies_1km=12))
        self.assertEqual(len(backend.messages), 2)

    def test_pending_request_is_never_skipped(self) -> None:
        backend = ScriptedBackend(Decision.wait("later"), Decision.wait("later"))
        director = Director(backend, self.log_dir, max_skip=300)
        director.decide({**STATE, "request": "send a patrol"})
        director.decide(STATE)
        self.assertEqual(len(backend.messages), 2)


if __name__ == "__main__":
    unittest.main()
