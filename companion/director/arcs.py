"""Story arcs: short plots the director plans on request (!director arc ...) and then steers towards over several
decisions.

An arc is planned once by Claude (title, premise, 3-5 beats, ending). Every decision while it runs shows Claude the
arc and its current beat; a decision with arc_beat_done moves it on, and finishing the last beat completes it. The
active arc is saved in the campaign (arc.json), so a restarted companion carries on with it.
"""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from pathlib import Path

from pydantic import BaseModel, ConfigDict, Field

MAX_BEATS = 5


class Beat(BaseModel):
    model_config = ConfigDict(extra="forbid")

    goal: str
    suggested_actions: str
    not_before_minute: int


class ArcPlan(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str
    premise: str
    beats: list[Beat] = Field(min_length=2, max_length=MAX_BEATS + 1)
    ending: str


ARC_SCHEMA = {
    "type": "object",
    "properties": {
        "title": {"type": "string"},
        "premise": {"type": "string"},
        "beats": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "goal": {"type": "string"},
                    "suggested_actions": {"type": "string"},
                    "not_before_minute": {"type": "integer"},
                },
                "required": ["goal", "suggested_actions", "not_before_minute"],
                "additionalProperties": False,
            },
        },
        "ending": {"type": "string"},
    },
    "required": ["title", "premise", "beats", "ending"],
    "additionalProperties": False,
}


@dataclass
class Arc:
    plan: dict
    asked_for: str
    started_game_time: float
    current: int = 0
    # One entry per finished beat: the game time and the decision's reason.
    done: list[dict] = field(default_factory=list)

    @classmethod
    def start(cls, plan: ArcPlan, asked_for: str, game_time: float) -> Arc:
        return cls(plan.model_dump(), asked_for, game_time)

    @property
    def title(self) -> str:
        return self.plan["title"]

    @property
    def beats(self) -> list[dict]:
        return self.plan["beats"]

    def advance(self, game_time: float, reason: str) -> bool:
        """Marks the current beat done; True when that was the last one."""
        self.done.append({"beat": self.current, "game_time": game_time, "how": reason})
        self.current += 1
        return self.current >= len(self.beats)

    def summary(self, event: str = "") -> dict:
        """What the game and the log see."""
        return {"title": self.title, "beat": min(self.current + 1, len(self.beats)), "beats": len(self.beats),
                "event": event}

    def describe(self, game_time: float) -> str:
        """The arc as shown to Claude with each decision."""
        minutes = max(0, round((game_time - self.started_game_time) / 60))
        lines = [
            f'"{self.title}", started {minutes} min ago ({self.asked_for or "the director chose it"}).',
            f"Premise: {self.plan['premise']}",
        ]
        for i, beat in enumerate(self.beats):
            state = "done" if i < self.current else "CURRENT" if i == self.current else "to come"
            lines.append(f"{i + 1}. [{state}] {beat['goal']} (suggested: {beat['suggested_actions']}; "
                         f"not before minute {beat['not_before_minute']})")
        lines.append(f"Ending: {self.plan['ending']}")
        return "\n".join(lines)

    def save(self, path: Path) -> None:
        path.write_text(json.dumps(asdict(self), indent=2) + "\n", encoding="utf-8")

    @classmethod
    def load(cls, path: Path) -> Arc | None:
        if not path.exists():
            return None
        return cls(**json.loads(path.read_text(encoding="utf-8")))
