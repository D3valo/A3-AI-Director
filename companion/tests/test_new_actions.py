import unittest

from director.catalogue import ACTIONS, Budget, Decision, check

PLAYER = {"name": "Alpha 1-1", "enemy_places": [{"place": "Kartsev Airbase", "held_by": "occupants", "distance": 900}]}
STATE = {"players": [PLAYER], "antistasi": {"war_level": 3}}


def act(action: str, **fields) -> Decision:
    return Decision.wait("test").model_copy(update={"action": action, **fields})


class NewActionTests(unittest.TestCase):
    def allowed(self, decision: Decision, state: dict = STATE) -> bool:
        return check(decision, state, Budget()).action == decision.action

    def test_allied_assault_place_must_be_offered(self) -> None:
        assault = act("allied_assault", target_player="Alpha 1-1", strength="squad")
        self.assertTrue(self.allowed(assault))
        self.assertTrue(self.allowed(assault.model_copy(update={"place": "Kartsev Airbase"})))
        self.assertFalse(self.allowed(assault.model_copy(update={"place": "Moscow"})))

    def test_reinforcements_need_strength_and_antistasi(self) -> None:
        self.assertFalse(self.allowed(act("send_reinforcements", target_player="Alpha 1-1")))
        reinforce = act("send_reinforcements", target_player="Alpha 1-1", strength="fireteam")
        self.assertTrue(self.allowed(reinforce))
        self.assertFalse(self.allowed(reinforce, {"players": [PLAYER]}))

    def test_change_aggression(self) -> None:
        self.assertFalse(self.allowed(act("change_aggression")))
        self.assertTrue(self.allowed(act("change_aggression", aggression="raise", enemy="invaders")))
        defeated = {**STATE, "antistasi": {"war_level": 3, "invaders_defeated": True}}
        self.assertFalse(self.allowed(act("change_aggression", aggression="raise", enemy="invaders"), defeated))

    def test_punishing_responses_are_hostile_and_capped(self) -> None:
        at_hq = {**STATE, "players": [{**PLAYER, "at_hq": True}], "director": {"protect_hq": "director"}}
        near_cap = {**STATE, "director": {"units_alive": 15, "units_max": 24}}
        armor = act("armor_assault", target_player="Alpha 1-1")
        self.assertTrue(self.allowed(armor))
        self.assertFalse(self.allowed(armor, at_hq))
        self.assertFalse(self.allowed(armor, near_cap))
        self.assertTrue(self.allowed(act("air_attack", target_player="Alpha 1-1"), near_cap))

    def test_friendly_actions_are_not_capped(self) -> None:
        self.assertEqual(ACTIONS["send_reinforcements"].soldiers, 0)
        self.assertEqual(ACTIONS["allied_assault"].soldiers, 0)


if __name__ == "__main__":
    unittest.main()
