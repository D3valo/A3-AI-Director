"""The actions the director may choose, the JSON schema Claude must answer in, and the checks applied
to every decision before it reaches the game.

Each action is described once in ACTIONS: the decision fields it needs, its cooldown, and whether it
needs Antistasi. The schema guarantees the shape; `check` enforces what a schema can't: per-action
required fields, that the target is a real player, game-state preconditions (including the cap on
director-spawned soldiers alive), and the cooldowns, unless the host turned them off in game (the state's
director.cooldowns).
"""

from __future__ import annotations

import time
from collections.abc import Callable
from dataclasses import dataclass, field
from typing import Literal

from pydantic import BaseModel, ConfigDict

Action = Literal[
    "wait", "narrate", "spawn_patrol", "call_support", "offer_mission", "launch_offensive",
    "reveal_enemies", "reward_rebels", "change_weather", "vehicle_patrol", "roadblock", "heli_recon",
    "sniper_team", "informant", "supply_drop", "enemy_vip", "armor_assault", "air_attack", "send_reinforcements",
    "allied_assault", "change_aggression", "antistasi_event", "counterattack", "waved_attack", "punish_town",
    "attack_hq",
]
Strength = Literal["fireteam", "squad"]
MissionType = Literal["assassination", "conquest", "destroy", "logistics", "supplies", "rescue", "convoy"]
Weather = Literal["clear", "overcast", "rain", "storm", "fog"]
Reward = Literal["small", "large"]
Enemy = Literal["occupants", "invaders"]
Aggression = Literal["raise", "lower"]
# Antistasi Ultimate's own random events (see AID_antistasiEvents in the game).
AntistasiEvent = Literal[
    "civilian_heli", "civilian_plane", "police_patrol", "police_skirmish", "police_hostages", "supply_truck",
    "outpost_patrol", "ambush_wreck", "ambushed_convoy", "battle_aftermath", "repair_crew", "medevac", "heli_slingload",
    "frontline_skirmish", "specops_airdrop", "rivals_car_bomb", "rivals_drone_strike", "rivals_roving_mortar",
    "rivals_heli_raid", "rivals_vs_occupants", "rivals_vs_police",
]
# Antistasi's support types (see AID_supportTypes in the game); which ones a side has is in the state.
SupportType = Literal[
    "airstrike", "carpet_bombs", "cruise_missile", "orbital_strike", "gunship", "artillery", "mortar", "howitzer",
    "cas", "cas_dive", "uav_attack", "tank", "qrf_land", "qrf_air", "qrf_vehicle_airdrop", "qrf_orbital",
    "air_superiority", "sam",
]
Waves = Literal[1, 2, 3]

# Antistasi's task codes, as listed in the state's active_missions.
MISSION_CODES: dict[str, str] = {
    "assassination": "AS", "conquest": "CON", "destroy": "DES", "logistics": "LOG",
    "supplies": "SUPP", "rescue": "RES", "convoy": "CONVOY",
}
# Hostile actions: carried out by the decision's enemy side, and never against a player at a protected HQ.
# (supply_drop also uses the enemy side, for whose crate is dropped; punish_town is always the invaders.)
HOSTILE_ACTIONS = frozenset({
    "spawn_patrol", "call_support", "launch_offensive", "vehicle_patrol", "roadblock", "heli_recon", "sniper_team",
    "enemy_vip", "armor_assault", "air_attack", "counterattack", "waved_attack", "punish_town", "attack_hq",
})
# Antistasi's major attacks: one at a time (big_attack_in_progress), each costing at least this many attack
# resources unless the host asked for it, and sharing one cooldown.
MAJOR_ATTACKS = ("launch_offensive", "waved_attack", "punish_town", "attack_hq")
OFFENSIVE_MIN_ATTACK_RESOURCES = 400
# Kinds of location Antistasi's own attacks go for, besides towns (punish_town) and the HQ (attack_hq).
ATTACKABLE_KINDS = frozenset({"airbase", "military base", "outpost", "seaport", "factory", "resource"})
# Antistasi runs one random event at a time and one Rivals event at a time: the state flag each event waits on.
# The two Rivals skirmishes run as random events (they clear that flag when they end).
RIVALS_EVENTS = frozenset({
    "rivals_car_bomb", "rivals_drone_strike", "rivals_roving_mortar", "rivals_heli_raid", "rivals_vs_occupants",
    "rivals_vs_police",
})
EVENT_FLAGS: dict[str, str] = {
    event: "rivals_event_running" if event in RIVALS_EVENTS - {"rivals_vs_occupants", "rivals_vs_police"}
    else "random_event_running"
    for event in AntistasiEvent.__args__
}
# Largest patrol of each strength (Antistasi fireteams are 5, vanilla ones 4), for the soldier cap; other
# encounters give their size in ActionSpec.soldiers.
PATROL_SIZE: dict[str, int] = {"fireteam": 5, "squad": 8}


@dataclass(frozen=True)
class ActionSpec:
    fields: tuple[str, ...] = ()
    cooldown: float = 0
    antistasi: bool = False
    # Most director soldiers it spawns, for the soldier cap.
    soldiers: int = 0


ACTIONS: dict[str, ActionSpec] = {
    "wait": ActionSpec(),
    "narrate": ActionSpec(("message",), cooldown=120),
    "spawn_patrol": ActionSpec(("target_player", "strength"), cooldown=600),
    "call_support": ActionSpec(("target_player",), cooldown=900, antistasi=True),
    "offer_mission": ActionSpec(("mission_type",), cooldown=1200, antistasi=True),
    "launch_offensive": ActionSpec(cooldown=3600, antistasi=True),
    "reveal_enemies": ActionSpec(("target_player",), cooldown=600),
    "reward_rebels": ActionSpec(("reward",), cooldown=1800, antistasi=True),
    "change_weather": ActionSpec(("weather",), cooldown=1200),
    "vehicle_patrol": ActionSpec(("target_player",), cooldown=900, antistasi=True, soldiers=8),
    "roadblock": ActionSpec(("target_player",), cooldown=1200, antistasi=True, soldiers=8),
    "heli_recon": ActionSpec(("target_player",), cooldown=900, antistasi=True),
    "sniper_team": ActionSpec(("target_player",), cooldown=900, antistasi=True, soldiers=2),
    # The informant's line is the optional message.
    "informant": ActionSpec(("target_player",), cooldown=1200),
    "supply_drop": ActionSpec(("target_player",), cooldown=1800, antistasi=True),
    "enemy_vip": ActionSpec(("target_player",), cooldown=1800, antistasi=True, soldiers=6),
    # Punishing responses for players who are doing very well.
    "armor_assault": ActionSpec(("target_player",), cooldown=1800, antistasi=True, soldiers=11),
    "air_attack": ActionSpec(("target_player",), cooldown=1800, antistasi=True, soldiers=4),
    # Friendly forces: rebel AI from the rebels' template, a gift that costs the rebels nothing.
    "send_reinforcements": ActionSpec(("target_player", "strength"), cooldown=1200, antistasi=True),
    "allied_assault": ActionSpec(("target_player", "strength"), cooldown=1800, antistasi=True),
    "change_aggression": ActionSpec(("aggression",), cooldown=1200, antistasi=True),
    # Antistasi Ultimate's own systems: its random events and attacks, which it pays for and sizes itself.
    "antistasi_event": ActionSpec(("event",), cooldown=900, antistasi=True),
    "counterattack": ActionSpec(("place",), cooldown=1800, antistasi=True),
    "waved_attack": ActionSpec(("place", "waves"), cooldown=3600, antistasi=True),
    "punish_town": ActionSpec(("place",), cooldown=3600, antistasi=True),
    "attack_hq": ActionSpec(cooldown=3600, antistasi=True),
}
COOLDOWN_SECONDS: dict[str, float] = {name: spec.cooldown for name, spec in ACTIONS.items() if spec.cooldown}


class Decision(BaseModel):
    model_config = ConfigDict(extra="forbid")

    action: Action
    reason: str
    message: str | None
    target_player: str | None
    strength: Strength | None
    mission_type: MissionType | None
    weather: Weather | None
    reward: Reward | None
    # Which enemy carries out a hostile action; null means the occupiers (or the game's AID_patrolSide).
    enemy: Enemy | None
    # allied_assault's target, by name from a player's enemy_places; null for the nearest.
    place: str | None
    aggression: Aggression | None
    # antistasi_event's event.
    event: AntistasiEvent | None
    # call_support's support type; null lets Antistasi choose.
    support_type: SupportType | None
    # waved_attack's number of waves.
    waves: Waves | None
    # True when this decision carries out the pending player request, or no action can satisfy it.
    request_done: bool
    # True when this decision delivers the active story arc's current beat (see arcs.py).
    arc_beat_done: bool

    @classmethod
    def wait(cls, reason: str) -> Decision:
        return cls(
            action="wait", reason=reason, message=None, target_player=None, strength=None,
            mission_type=None, weather=None, reward=None, enemy=None, place=None, aggression=None, event=None,
            support_type=None, waves=None, request_done=False, arc_beat_done=False,
        )


def _nullable(schema: dict) -> dict:
    return {"anyOf": [schema, {"type": "null"}]}


def _enum(literal) -> dict:
    return {"type": "string", "enum": list(literal.__args__)}


# Structured outputs need every property listed in `required` and `additionalProperties: false`;
# fields an action doesn't use are null. Keep in step with `Decision` (tests check this).
DECISION_SCHEMA = {
    "type": "object",
    "properties": {
        "action": _enum(Action),
        "reason": {"type": "string"},
        "message": _nullable({"type": "string"}),
        "target_player": _nullable({"type": "string"}),
        "strength": _nullable(_enum(Strength)),
        "mission_type": _nullable(_enum(MissionType)),
        "weather": _nullable(_enum(Weather)),
        "reward": _nullable(_enum(Reward)),
        "enemy": _nullable(_enum(Enemy)),
        "place": _nullable({"type": "string"}),
        "aggression": _nullable(_enum(Aggression)),
        "event": _nullable(_enum(AntistasiEvent)),
        "support_type": _nullable(_enum(SupportType)),
        "waves": _nullable({"type": "integer", "enum": list(Waves.__args__)}),
        "request_done": {"type": "boolean"},
        "arc_beat_done": {"type": "boolean"},
    },
    "required": [
        "action", "reason", "message", "target_player", "strength", "mission_type", "weather", "reward", "enemy", "place",
        "aggression", "event", "support_type", "waves",
        "request_done", "arc_beat_done",
    ],
    "additionalProperties": False,
}

# Actions that only tell a story; with narrative off (--no-narrative) the director can't choose them.
NARRATIVE_ACTIONS = frozenset({"narrate"})


def decision_schema(narrative: bool = True) -> dict:
    """DECISION_SCHEMA, without the actions that only tell a story when `narrative` is off."""
    if narrative:
        return DECISION_SCHEMA
    actions = [name for name in ACTIONS if name not in NARRATIVE_ACTIONS]
    properties = {**DECISION_SCHEMA["properties"], "action": {"type": "string", "enum": actions}}
    return {**DECISION_SCHEMA, "properties": properties}


MAX_MESSAGE_CHARS = 200
MAX_REQUEST_CHARS = 300
# Actions that also start another's cooldown: the informant's intel marks the same enemies reveal_enemies does.
SHARED_COOLDOWNS: dict[str, tuple[str, ...]] = {
    "informant": ("reveal_enemies",),
    **{attack: tuple(other for other in MAJOR_ATTACKS if other != attack) for attack in MAJOR_ATTACKS},
}


@dataclass
class Budget:
    """Cooldowns per action, measured in real seconds since the companion started."""

    clock: Callable[[], float] = time.monotonic
    last_used: dict[str, float] = field(default_factory=dict)

    def remaining(self, action: str) -> float:
        cooldown = COOLDOWN_SECONDS.get(action, 0)
        last = self.last_used.get(action)
        return 0.0 if last is None else max(0.0, last + cooldown - self.clock())

    def spend(self, action: str) -> None:
        for name in (action, *SHARED_COOLDOWNS.get(action, ())):
            self.last_used[name] = self.clock()

    def cooling_down(self) -> dict[str, float]:
        """Actions still on cooldown, with the seconds left."""
        return {name: left for name in COOLDOWN_SECONDS if (left := self.remaining(name)) > 0}


def check(
    decision: Decision, state: dict, budget: Budget, host_request: bool = False, narrative: bool = True
) -> Decision:
    """Returns the decision if it may run, otherwise a `wait` that records why it was dropped. With a host request
    pending, a major attack may push its side into debt. With narrative off, actions that only tell a story are
    rejected and an informant says its stock line. With the cooldowns off in game, an action may run while on
    cooldown (and still starts it, for when they're turned on again)."""
    if not narrative and decision.action in NARRATIVE_ACTIONS:
        problem = "narrative is off"
    else:
        problem = _problem(decision, state, budget, host_request)
    if problem:
        return Decision.wait(f"rejected {decision.action}: {problem} (Claude's reason: {decision.reason})")
    if decision.action != "wait":
        budget.spend(decision.action)
    if not narrative and decision.message is not None:
        decision = decision.model_copy(update={"message": None})
    return decision


def _problem(decision: Decision, state: dict, budget: Budget, host_request: bool) -> str | None:
    spec = ACTIONS[decision.action]
    antistasi = state.get("antistasi", {})
    if spec.antistasi and antistasi.get("war_level", -1) < 0:
        return "needs Antistasi"
    for name in spec.fields:
        if getattr(decision, name) is None:
            return f"no {name}"
    players = {p.get("name"): p for p in state.get("players", [])}
    if "target_player" in spec.fields and decision.target_player not in players:
        return f"unknown target player {decision.target_player!r}"
    enemy = "invaders" if decision.action == "punish_town" else decision.enemy or "occupants"
    if decision.action in HOSTILE_ACTIONS:
        if decision.enemy and antistasi.get("war_level", -1) < 0:
            return "choosing the enemy side needs Antistasi"
        if antistasi.get(f"{enemy}_defeated"):
            return f"the {enemy} are defeated"
        target = players.get(decision.target_player, {})
        if target.get("at_hq") and state.get("director", {}).get("protect_hq", "off") != "off":
            return f"{decision.target_player} is at the protected rebel HQ"

    director = state.get("director", {})
    soldiers = PATROL_SIZE[decision.strength] if decision.action == "spawn_patrol" else spec.soldiers
    if soldiers and director.get("units_alive", 0) + soldiers > director.get("units_max", float("inf")):
        return f"too many director soldiers alive ({director['units_alive']} of {director['units_max']})"
    match decision.action:
        case "allied_assault" if decision.place and decision.place not in {
            place.get("place") for p in players.values() for place in p.get("enemy_places", [])
        }:
            return f"unknown target place {decision.place!r} (use one from a player's enemy_places)"
        case "change_aggression" if antistasi.get(f"{decision.enemy or 'occupants'}_defeated"):
            return f"the {decision.enemy or 'occupants'} are defeated"
        case "narrate" | "informant" if decision.message and len(decision.message) > MAX_MESSAGE_CHARS:
            return f"message longer than {MAX_MESSAGE_CHARS} characters"
        case "offer_mission" if MISSION_CODES[decision.mission_type] in antistasi.get("active_missions", []):
            return f"a {decision.mission_type} mission is already active"
        case action if action in MAJOR_ATTACKS and antistasi.get("big_attack_in_progress"):
            return "a big attack is already in progress"
        case action if action in MAJOR_ATTACKS and not host_request and (
            antistasi.get(f"{enemy}_attack_resources", 0) < OFFENSIVE_MIN_ATTACK_RESOURCES
        ):
            return f"the {enemy} can't afford a major attack"
        case "call_support" if decision.support_type and "support_types" in antistasi and (
            decision.support_type not in antistasi["support_types"].get(enemy, [])
        ):
            return (f"the {enemy} have no {decision.support_type} support (they have: "
                    f"{', '.join(antistasi['support_types'].get(enemy, [])) or 'none'})")
        case "antistasi_event" if decision.event in RIVALS_EVENTS and not antistasi.get("rivals_active"):
            return "the Rivals are not active"
        case "antistasi_event" if antistasi.get(EVENT_FLAGS[decision.event]):
            kind = "Rivals event" if EVENT_FLAGS[decision.event] == "rivals_event_running" else "random event"
            return f"another Antistasi {kind} is still running"
        case "counterattack" | "waved_attack" | "punish_town" if (
            problem := _place_problem(decision, antistasi, players, enemy)
        ):
            return problem
        case "attack_hq" if state.get("director", {}).get("protect_hq", "off") != "off":
            return "the rebel HQ is protected (the host can lift that with !director hq off)"

    remaining = budget.remaining(decision.action)
    if remaining > 0 and state.get("director", {}).get("cooldowns", True):
        return f"on cooldown for {remaining:.0f} s"
    return None


def _place_problem(decision: Decision, antistasi: dict, players: dict[str, dict], enemy: str) -> str | None:
    """Whether the place an attack names is one it may go for: a rebel-held base for counterattack, a base held by
    the rebels or the other enemy for waved_attack, a rebel-held town for punish_town (with punishments allowed)."""
    if decision.action == "punish_town" and not antistasi.get("punishments_allowed"):
        return "punishments are off in this campaign or the war level is too low"
    places = {p.get("place"): {**p, "held_by": "rebels"} for p in antistasi.get("rebel_places", [])}
    sources = "rebel_places"
    if decision.action == "waved_attack":
        places |= {place.get("place"): place for p in players.values() for place in p.get("enemy_places", [])}
        sources += " or a player's enemy_places"
    place = places.get(decision.place)
    if place is None:
        return f"unknown target place {decision.place!r} (use one from {sources})"
    if place.get("held_by") == enemy:
        return f"{decision.place} is already held by the {enemy}"
    kinds = {"town"} if decision.action == "punish_town" else ATTACKABLE_KINDS
    if place.get("kind") not in kinds:
        return (f"{decision.place} is of kind {place.get('kind')}; {decision.action} needs one of: "
                f"{', '.join(sorted(kinds))}")
    return None
