"""Antistasi's own systems (random events, chosen supports, counterattacks and major attacks), and cooldowns the host
can turn off in game."""
import tempfile
import unittest
from pathlib import Path

from director.catalogue import Budget, Decision, check
from director.decider import Director
from tests.test_decider import ScriptedBackend
from tests.test_new_actions import act

PLAYER = {
    "name": "Alpha 1-1",
    "enemy_places": [
        {"place": "Kartsev Airbase", "kind": "airbase", "held_by": "occupants", "distance": 900},
        {"place": "Zavod Factory", "kind": "factory", "held_by": "invaders", "distance": 1400},
    ],
}
ANTISTASI = {
    "war_level": 5, "occupants_attack_resources": 900, "invaders_attack_resources": 900,
    "support_types": {"occupants": ["qrf_land", "mortar"], "invaders": ["cas"]},
    "rivals_active": True, "random_event_running": False, "rivals_event_running": False,
    "punishments_allowed": True,
    "rebel_places": [
        {"place": "Outpost Bravo", "kind": "outpost", "nearest_player": 600},
        {"place": "Lopatino", "kind": "town", "nearest_player": 1200},
        {"place": "Roadblock (grid 041112)", "kind": "roadblock", "nearest_player": 300},
    ],
}
STATE = {"players": [PLAYER], "antistasi": ANTISTASI, "director": {"protect_hq": "director", "cooldowns": True}}


def with_antistasi(**changes) -> dict:
    return {**STATE, "antistasi": {**ANTISTASI, **changes}}


class AntistasiSystemTests(unittest.TestCase):
    def problem(self, decision: Decision, state: dict = STATE, budget: Budget | None = None) -> str | None:
        checked = check(decision, state, budget or Budget())
        return None if checked.action == decision.action else checked.reason

    def assertAllowed(self, decision: Decision, state: dict = STATE) -> None:
        self.assertIsNone(self.problem(decision, state))

    def assertRejected(self, decision: Decision, why: str, state: dict = STATE) -> None:
        self.assertIn(why, self.problem(decision, state) or "allowed")

    def test_call_support_type(self) -> None:
        support = act("call_support", target_player="Alpha 1-1")
        self.assertAllowed(support)
        self.assertAllowed(support.model_copy(update={"support_type": "mortar"}))
        self.assertRejected(support.model_copy(update={"support_type": "cas"}), "have no cas support (they have: ")
        self.assertAllowed(support.model_copy(update={"support_type": "cas", "enemy": "invaders"}))

    def test_antistasi_events_wait_their_turn(self) -> None:
        self.assertRejected(act("antistasi_event"), "no event")
        self.assertAllowed(act("antistasi_event", event="police_patrol"))
        self.assertRejected(act("antistasi_event", event="police_patrol"), "random event is still running",
                            with_antistasi(random_event_running=True))
        # A running Rivals event holds back only the Rivals' own events, not their skirmishes.
        rivals_busy = with_antistasi(rivals_event_running=True)
        self.assertRejected(act("antistasi_event", event="rivals_heli_raid"), "Rivals event is still running",
                            rivals_busy)
        self.assertAllowed(act("antistasi_event", event="rivals_vs_police"), rivals_busy)
        self.assertRejected(act("antistasi_event", event="rivals_vs_police"), "random event is still running",
                            with_antistasi(random_event_running=True))
        self.assertRejected(act("antistasi_event", event="rivals_car_bomb"), "Rivals are not active",
                            with_antistasi(rivals_active=False))

    def test_counterattack_targets_rebel_bases(self) -> None:
        self.assertAllowed(act("counterattack", place="Outpost Bravo"))
        self.assertRejected(act("counterattack", place="Lopatino"), "is of kind town")
        self.assertRejected(act("counterattack", place="Roadblock (grid 041112)"), "is of kind roadblock")
        self.assertRejected(act("counterattack", place="Kartsev Airbase"), "use one from rebel_places)")

    def test_waved_attack_targets(self) -> None:
        waved = act("waved_attack", place="Outpost Bravo", waves=2)
        self.assertAllowed(waved)
        self.assertRejected(act("waved_attack", place="Outpost Bravo"), "no waves")
        # A base of the other enemy, but not one the attacking side already holds.
        self.assertAllowed(waved.model_copy(update={"place": "Zavod Factory"}))
        self.assertRejected(waved.model_copy(update={"place": "Kartsev Airbase"}), "already held by the occupants")
        self.assertAllowed(waved.model_copy(update={"place": "Kartsev Airbase", "enemy": "invaders"}))

    def test_major_attacks_one_at_a_time_and_paid_for(self) -> None:
        attacks = [
            act("launch_offensive"), act("waved_attack", place="Outpost Bravo", waves=1),
            act("punish_town", place="Lopatino"), act("attack_hq"),
        ]
        hq_open = {**STATE, "director": {"protect_hq": "off"}}
        busy = {**hq_open, "antistasi": {**ANTISTASI, "big_attack_in_progress": True}}
        broke = {**hq_open, "antistasi": {**ANTISTASI, "occupants_attack_resources": -1600,
                                           "invaders_attack_resources": -300}}
        for attack in attacks:
            self.assertAllowed(attack, hq_open)
            self.assertRejected(attack, "a big attack is already in progress", busy)
            self.assertRejected(attack, "can't afford a major attack", broke)
            self.assertEqual(check(attack, broke, Budget(), host_request=True).action, attack.action)

    def test_major_attacks_share_a_cooldown(self) -> None:
        budget = Budget()
        state = {**STATE, "director": {"protect_hq": "off"}}
        self.assertEqual(check(act("launch_offensive"), state, budget).action, "launch_offensive")
        for attack in (act("waved_attack", place="Outpost Bravo", waves=3), act("punish_town", place="Lopatino"),
                       act("attack_hq")):
            self.assertIn("on cooldown", self.problem(attack, state, budget))
        self.assertIsNone(self.problem(act("counterattack", place="Outpost Bravo"), state, budget))

    def test_punish_town(self) -> None:
        self.assertAllowed(act("punish_town", place="Lopatino"))
        self.assertRejected(act("punish_town", place="Outpost Bravo"), "is of kind outpost")
        self.assertRejected(act("punish_town", place="Lopatino"), "punishments are off",
                            with_antistasi(punishments_allowed=False))
        self.assertRejected(act("punish_town", place="Lopatino"), "the invaders are defeated",
                            with_antistasi(invaders_defeated=True))

    def test_attack_hq_only_unprotected(self) -> None:
        self.assertRejected(act("attack_hq"), "the rebel HQ is protected")
        self.assertAllowed(act("attack_hq"), {**STATE, "director": {"protect_hq": "off"}})

    def test_cooldowns_off_in_game(self) -> None:
        budget = Budget()
        patrol = act("spawn_patrol", target_player="Alpha 1-1", strength="squad")
        self.assertEqual(check(patrol, STATE, budget).action, "spawn_patrol")
        self.assertIn("on cooldown", self.problem(patrol, STATE, budget))
        cooldowns_off = {**STATE, "director": {"cooldowns": False}}
        self.assertIsNone(self.problem(patrol, cooldowns_off, budget))
        # Other rules still hold.
        self.assertRejected(act("antistasi_event", event="medevac"), "random event is still running",
                            {**cooldowns_off, "antistasi": {**ANTISTASI, "random_event_running": True}})

    def test_claude_hears_cooldowns_are_off(self) -> None:
        patrol = act("spawn_patrol", target_player="Alpha 1-1", strength="squad")
        backend = ScriptedBackend(patrol, Decision.wait("a"), Decision.wait("b"))
        director = Director(backend, Path(tempfile.mkdtemp()))
        director.decide(STATE)
        director.decide(STATE)
        director.decide({**STATE, "director": {"cooldowns": False}})
        self.assertIn("\nspawn_patrol (10)\n", backend.messages[1])
        self.assertIn("\nnone: the host turned the cooldowns off", backend.messages[2])


if __name__ == "__main__":
    unittest.main()
