import unittest

from director.catalogue import COOLDOWN_SECONDS, DECISION_SCHEMA, Budget, Decision, check

STATE = {"players": [{"name": "Alpha 1-1"}]}


class FakeClock:
    def __init__(self) -> None:
        self.now = 0.0

    def __call__(self) -> float:
        return self.now


def decision(action: str, **fields) -> Decision:
    return Decision(**{"reason": "test", "message": None, "target_player": None, "strength": None, "request_done": False, "action": action, **fields})


class CatalogueTests(unittest.TestCase):
    def setUp(self) -> None:
        self.clock = FakeClock()
        self.budget = Budget(clock=self.clock)

    def test_schema_matches_model(self) -> None:
        self.assertEqual(set(DECISION_SCHEMA["properties"]), set(Decision.model_fields))
        self.assertEqual(set(DECISION_SCHEMA["required"]), set(Decision.model_fields))

    def test_wait_always_allowed(self) -> None:
        self.assertEqual(check(decision("wait"), STATE, self.budget).action, "wait")
        self.assertEqual(check(decision("wait"), STATE, self.budget).action, "wait")

    def test_spawn_needs_known_player_and_strength(self) -> None:
        self.assertEqual(check(decision("spawn_patrol", target_player="Bravo", strength="squad"), STATE, self.budget).action, "wait")
        self.assertEqual(check(decision("spawn_patrol", target_player="Alpha 1-1"), STATE, self.budget).action, "wait")
        ok = check(decision("spawn_patrol", target_player="Alpha 1-1", strength="squad"), STATE, self.budget)
        self.assertEqual(ok.action, "spawn_patrol")

    def test_cooldown(self) -> None:
        spawn = decision("spawn_patrol", target_player="Alpha 1-1", strength="fireteam")
        self.assertEqual(check(spawn, STATE, self.budget).action, "spawn_patrol")
        rejected = check(spawn, STATE, self.budget)
        self.assertEqual(rejected.action, "wait")
        self.assertIn("cooldown", rejected.reason)
        self.clock.now += COOLDOWN_SECONDS["spawn_patrol"]
        self.assertEqual(check(spawn, STATE, self.budget).action, "spawn_patrol")

    def test_narrate_needs_short_message(self) -> None:
        self.assertEqual(check(decision("narrate"), STATE, self.budget).action, "wait")
        self.assertEqual(check(decision("narrate", message="x" * 201), STATE, self.budget).action, "wait")
        self.assertEqual(check(decision("narrate", message="Static on the radio."), STATE, self.budget).action, "narrate")


if __name__ == "__main__":
    unittest.main()
