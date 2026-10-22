import unittest

from director.catalogue import ACTIONS, COOLDOWN_SECONDS, DECISION_SCHEMA, Budget, Decision, check

STATE = {"players": [{"name": "Alpha 1-1"}]}
ANTISTASI = {
    **STATE,
    "antistasi": {"war_level": 3, "occupants_attack_resources": 1000, "active_missions": ["CON"],
                  "big_attack_in_progress": False},
}


class FakeClock:
    def __init__(self) -> None:
        self.now = 0.0

    def __call__(self) -> float:
        return self.now


def decision(action: str, **fields) -> Decision:
    return Decision.wait("test").model_copy(update={"action": action, **fields})


class CatalogueTests(unittest.TestCase):
    def setUp(self) -> None:
        self.clock = FakeClock()
        self.budget = Budget(clock=self.clock)

    def allowed(self, d: Decision, state: dict = STATE) -> bool:
        return check(d, state, self.budget).action == d.action

    def test_schema_matches_model(self) -> None:
        self.assertEqual(set(DECISION_SCHEMA["properties"]), set(Decision.model_fields))
        self.assertEqual(set(DECISION_SCHEMA["required"]), set(Decision.model_fields))
        self.assertEqual(DECISION_SCHEMA["properties"]["action"]["enum"], list(ACTIONS))

    def test_every_action_field_is_a_decision_field(self) -> None:
        for spec in ACTIONS.values():
            self.assertTrue(set(spec.fields) <= set(Decision.model_fields))

    def test_wait_always_allowed(self) -> None:
        self.assertTrue(self.allowed(decision("wait")))
        self.assertTrue(self.allowed(decision("wait")))

    def test_required_fields(self) -> None:
        self.assertFalse(self.allowed(decision("spawn_patrol", target_player="Alpha 1-1")))
        self.assertFalse(self.allowed(decision("offer_mission"), ANTISTASI))
        self.assertFalse(self.allowed(decision("change_weather")))

    def test_target_must_be_a_player(self) -> None:
        self.assertFalse(self.allowed(decision("spawn_patrol", target_player="Bravo", strength="squad")))
        self.assertTrue(self.allowed(decision("spawn_patrol", target_player="Alpha 1-1", strength="squad")))

    def test_antistasi_only_actions(self) -> None:
        self.assertFalse(self.allowed(decision("call_support", target_player="Alpha 1-1")))
        self.assertTrue(self.allowed(decision("call_support", target_player="Alpha 1-1"), ANTISTASI))
        self.assertFalse(self.allowed(decision("reward_rebels", reward="small")))
        self.assertTrue(self.allowed(decision("change_weather", weather="fog")))

    def test_mission_type_not_already_active(self) -> None:
        self.assertFalse(self.allowed(decision("offer_mission", mission_type="conquest"), ANTISTASI))
        self.assertTrue(self.allowed(decision("offer_mission", mission_type="convoy"), ANTISTASI))

    def test_offensive_preconditions(self) -> None:
        busy = {**ANTISTASI, "antistasi": {**ANTISTASI["antistasi"], "big_attack_in_progress": True}}
        poor = {**ANTISTASI, "antistasi": {**ANTISTASI["antistasi"], "occupants_attack_resources": 100}}
        self.assertFalse(self.allowed(decision("launch_offensive"), busy))
        self.assertFalse(self.allowed(decision("launch_offensive"), poor))
        self.assertTrue(self.allowed(decision("launch_offensive"), ANTISTASI))

    def test_soldier_cap(self) -> None:
        def with_alive(alive: int) -> dict:
            return {**STATE, "director": {"units_alive": alive, "units_max": 24}}

        squad = decision("spawn_patrol", target_player="Alpha 1-1", strength="squad")
        fireteam = decision("spawn_patrol", target_player="Alpha 1-1", strength="fireteam")
        self.assertFalse(self.allowed(squad, with_alive(17)))
        self.assertTrue(self.allowed(fireteam, with_alive(19)))

    def test_cooldown(self) -> None:
        spawn = decision("spawn_patrol", target_player="Alpha 1-1", strength="fireteam")
        self.assertTrue(self.allowed(spawn))
        rejected = check(spawn, STATE, self.budget)
        self.assertEqual(rejected.action, "wait")
        self.assertIn("cooldown", rejected.reason)
        self.clock.now += COOLDOWN_SECONDS["spawn_patrol"]
        self.assertTrue(self.allowed(spawn))

    def test_narrate_needs_short_message(self) -> None:
        self.assertFalse(self.allowed(decision("narrate")))
        self.assertFalse(self.allowed(decision("narrate", message="x" * 201)))
        self.assertTrue(self.allowed(decision("narrate", message="Static on the radio.")))


if __name__ == "__main__":
    unittest.main()
