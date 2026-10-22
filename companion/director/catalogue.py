"""The events the director may choose, the JSON schema Claude must answer in, and the checks applied
to every decision before it reaches the game.

The schema guarantees the shape; `check` enforces what a schema can't: per-action required fields,
that the target is a real player, and the spawn and cooldown budgets.
"""

from __future__ import annotations

import time
from collections.abc import Callable
from dataclasses import dataclass, field
from typing import Literal

from pydantic import BaseModel, ConfigDict

Action = Literal["wait", "narrate", "spawn_patrol", "call_support"]
Strength = Literal["fireteam", "squad"]


class Decision(BaseModel):
    model_config = ConfigDict(extra="forbid")

    action: Action
    reason: str
    message: str | None
    target_player: str | None
    strength: Strength | None
    # True when this decision carries out the pending player request, or no action can satisfy it.
    request_done: bool

    @classmethod
    def wait(cls, reason: str) -> Decision:
        return cls(action="wait", reason=reason, message=None, target_player=None, strength=None, request_done=False)


def _nullable(schema: dict) -> dict:
    return {"anyOf": [schema, {"type": "null"}]}


# Structured outputs need every property listed in `required` and `additionalProperties: false`;
# optional fields are expressed as nullable. Keep in step with `Decision` (tests check this).
DECISION_SCHEMA = {
    "type": "object",
    "properties": {
        "action": {"type": "string", "enum": ["wait", "narrate", "spawn_patrol", "call_support"]},
        "reason": {"type": "string"},
        "message": _nullable({"type": "string"}),
        "target_player": _nullable({"type": "string"}),
        "strength": _nullable({"type": "string", "enum": ["fireteam", "squad"]}),
        "request_done": {"type": "boolean"},
    },
    "required": ["action", "reason", "message", "target_player", "strength", "request_done"],
    "additionalProperties": False,
}

MAX_MESSAGE_CHARS = 200
MAX_REQUEST_CHARS = 300
COOLDOWN_SECONDS: dict[str, float] = {"narrate": 120, "spawn_patrol": 600, "call_support": 900}


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
    match decision.action:
        case "wait":
            return None
        case "narrate":
            if not decision.message:
                return "no message"
            if len(decision.message) > MAX_MESSAGE_CHARS:
                return f"message longer than {MAX_MESSAGE_CHARS} characters"
        case "spawn_patrol":
            if not _is_player(decision.target_player, state):
                return f"unknown target player {decision.target_player!r}"
            if decision.strength is None:
                return "no strength"
        case "call_support":
            if state.get("antistasi", {}).get("war_level", -1) < 0:
                return "support needs Antistasi"
            if not _is_player(decision.target_player, state):
                return f"unknown target player {decision.target_player!r}"
    remaining = budget.remaining(decision.action)
    if remaining > 0:
        return f"on cooldown for {remaining:.0f} s"
    return None


def _is_player(name: str | None, state: dict) -> bool:
    return name in {p.get("name") for p in state.get("players", [])}
