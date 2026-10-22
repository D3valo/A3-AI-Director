"""The actions the director may choose, the JSON schema Claude must answer in, and the checks applied
to every decision before it reaches the game.

Each action is described once in ACTIONS: the decision fields it needs, its cooldown, and whether it
needs Antistasi. The schema guarantees the shape; `check` enforces what a schema can't: per-action
required fields, that the target is a real player, game-state preconditions (including the cap on
director-spawned soldiers alive), and the cooldowns.
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
    "allied_assault", "change_aggression",
]
Strength = Literal["fireteam", "squad"]
MissionType = Literal["assassination", "conquest", "destroy", "logistics", "supplies", "rescue", "convoy"]
Weather = Literal["clear", "overcast", "rain", "storm", "fog"]
Reward = Literal["small", "large"]
Enemy = Literal["occupants", "invaders"]
Aggression = Literal["raise", "lower"]

# Antistasi's task codes, as listed in the state's active_missions.
MISSION_CODES: dict[str, str] = {
    "assassination": "AS", "conquest": "CON", "destroy": "DES", "logistics": "LOG",
    "supplies": "SUPP", "rescue": "RES", "convoy": "CONVOY",
}
# Hostile actions: carried out by the decision's enemy side, and never against a player at a protected HQ.
# (supply_drop also uses the enemy side, for whose crate is dropped.)
HOSTILE_ACTIONS = frozenset({
    "spawn_patrol", "call_support", "launch_offensive", "vehicle_patrol", "roadblock", "heli_recon", "sniper_team",
    "enemy_vip", "armor_assault", "air_attack",
})
# Antistasi's attack costs at least this many attack resources.
OFFENSIVE_MIN_ATTACK_RESOURCES = 400
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
    # True when this decision carries out the pending player request, or no action can satisfy it.
    request_done: bool
    # True when this decision delivers the active story arc's current beat (see arcs.py).
    arc_beat_done: bool

    @classmethod
    def wait(cls, reason: str) -> Decision:
        return cls(
            action="wait", reason=reason, message=None, target_player=None, strength=None,
            mission_type=None, weather=None, reward=None, enemy=None, place=None, aggression=None, request_done=False, arc_beat_done=False,
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
        "request_done": {"type": "boolean"},
        "arc_beat_done": {"type": "boolean"},
    },
    "required": [
        "action", "reason", "message", "target_player", "strength", "mission_type", "weather", "reward", "enemy", "place",
        "aggression",
        "request_done", "arc_beat_done",
    ],
    "additionalProperties": False,
}

MAX_MESSAGE_CHARS = 200
MAX_REQUEST_CHARS = 300
# Actions that also start another's cooldown: the informant's intel marks the same enemies reveal_enemies does.
SHARED_COOLDOWNS: dict[str, tuple[str, ...]] = {"informant": ("reveal_enemies",)}


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


def check(decision: Decision, state: dict, budget: Budget, host_request: bool = False) -> Decision:
    """Returns the decision if it may run, otherwise a `wait` that records why it was dropped. With a host request
    pending, an offensive may push its side into debt."""
    problem = _problem(decision, state, budget, host_request)
    if problem:
        return Decision.wait(f"rejected {decision.action}: {problem} (Claude's reason: {decision.reason})")
    if decision.action != "wait":
        budget.spend(decision.action)
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
    if decision.action in HOSTILE_ACTIONS:
        enemy = decision.enemy or "occupants"
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
        case "launch_offensive" if antistasi.get("big_attack_in_progress"):
            return "a big attack is already in progress"
        case "launch_offensive" if not host_request and (
            antistasi.get(f"{decision.enemy or 'occupants'}_attack_resources", 0) < OFFENSIVE_MIN_ATTACK_RESOURCES
        ):
            return f"the {decision.enemy or 'occupants'} can't afford an offensive"

    remaining = budget.remaining(decision.action)
    if remaining > 0:
        return f"on cooldown for {remaining:.0f} s"
    return None
