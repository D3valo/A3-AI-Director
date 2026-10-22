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
    "reveal_enemies", "reward_rebels", "change_weather",
]
Strength = Literal["fireteam", "squad"]
MissionType = Literal["assassination", "conquest", "destroy", "logistics", "supplies", "rescue", "convoy"]
Weather = Literal["clear", "overcast", "rain", "storm", "fog"]
Reward = Literal["small", "large"]

# Antistasi's task codes, as listed in the state's active_missions.
MISSION_CODES: dict[str, str] = {
    "assassination": "AS", "conquest": "CON", "destroy": "DES", "logistics": "LOG",
    "supplies": "SUPP", "rescue": "RES", "convoy": "CONVOY",
}
# Antistasi's attack costs at least this many attack resources.
OFFENSIVE_MIN_ATTACK_RESOURCES = 400
# Largest patrol of each strength (Antistasi fireteams are 5, vanilla ones 4), for the soldier cap.
PATROL_SIZE: dict[str, int] = {"fireteam": 5, "squad": 8}


@dataclass(frozen=True)
class ActionSpec:
    fields: tuple[str, ...] = ()
    cooldown: float = 0
    antistasi: bool = False


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
    # True when this decision carries out the pending player request, or no action can satisfy it.
    request_done: bool

    @classmethod
    def wait(cls, reason: str) -> Decision:
        return cls(
            action="wait", reason=reason, message=None, target_player=None, strength=None,
            mission_type=None, weather=None, reward=None, request_done=False,
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
        "request_done": {"type": "boolean"},
    },
    "required": [
        "action", "reason", "message", "target_player", "strength", "mission_type", "weather", "reward",
        "request_done",
    ],
    "additionalProperties": False,
}

MAX_MESSAGE_CHARS = 200
MAX_REQUEST_CHARS = 300


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
        self.last_used[action] = self.clock()


def check(decision: Decision, state: dict, budget: Budget) -> Decision:
    """Returns the decision if it may run, otherwise a `wait` that records why it was dropped."""
    problem = _problem(decision, state, budget)
    if problem:
        return Decision.wait(f"rejected {decision.action}: {problem} (Claude's reason: {decision.reason})")
    if decision.action != "wait":
        budget.spend(decision.action)
    return decision


def _problem(decision: Decision, state: dict, budget: Budget) -> str | None:
    spec = ACTIONS[decision.action]
    antistasi = state.get("antistasi", {})
    if spec.antistasi and antistasi.get("war_level", -1) < 0:
        return "needs Antistasi"
    for name in spec.fields:
        if getattr(decision, name) is None:
            return f"no {name}"
    if "target_player" in spec.fields and decision.target_player not in {p.get("name") for p in state.get("players", [])}:
        return f"unknown target player {decision.target_player!r}"

    director = state.get("director", {})
    match decision.action:
        case "spawn_patrol" if (
            director.get("units_alive", 0) + PATROL_SIZE[decision.strength] > director.get("units_max", float("inf"))
        ):
            return f"too many director soldiers alive ({director['units_alive']} of {director['units_max']})"
        case "narrate" if len(decision.message) > MAX_MESSAGE_CHARS:
            return f"message longer than {MAX_MESSAGE_CHARS} characters"
        case "offer_mission" if MISSION_CODES[decision.mission_type] in antistasi.get("active_missions", []):
            return f"a {decision.mission_type} mission is already active"
        case "launch_offensive" if antistasi.get("big_attack_in_progress"):
            return "a big attack is already in progress"
        case "launch_offensive" if antistasi.get("occupants_attack_resources", 0) < OFFENSIVE_MIN_ATTACK_RESOURCES:
            return "the occupiers can't afford an offensive"

    remaining = budget.remaining(decision.action)
    if remaining > 0:
        return f"on cooldown for {remaining:.0f} s"
    return None
