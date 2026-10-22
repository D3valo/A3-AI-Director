"""Turns a game state into a checked decision, using one of the backends in backends.py."""

from __future__ import annotations

import json
import logging
import threading
import time
from collections import deque
from datetime import datetime, timezone
from pathlib import Path

from pydantic import ValidationError

from . import personalities
from .arcs import ARC_SCHEMA, Arc, ArcPlan
from .backends import Backend
from .catalogue import DECISION_SCHEMA, MAX_REQUEST_CHARS, Budget, Decision, check
from .pacing import Pacer
from .prompt import ARC_PROMPT, system_prompt

log = logging.getLogger(__name__)

RECENT_DECISIONS = 5
DECISION_TIMEOUT_SECONDS = 120
ARC_EFFORT = "medium"
ARC_TIMEOUT_SECONDS = 180
DEFAULT_MAX_SKIP_SECONDS = 300


class Director:
    def __init__(
        self,
        backend: Backend,
        log_dir: Path,
        effort: str = "low",
        story: str | None = None,
        personality: str = personalities.DEFAULT,
        max_skip: float = 0,
        styles: dict[str, str] | None = None,
        arc_path: Path | None = None,
    ) -> None:
        self.backend = backend
        self.effort = effort
        # The campaign's story so far, read once per session.
        self.story = story
        # The session's style, unless the game asks for another (!director style ...).
        self.styles = styles if styles is not None else dict(personalities.BUILT_IN)
        self.personality = personality
        # The style the last decision used, reported back to the game.
        self.last_personality = personality
        self.pacer = Pacer(max_skip)
        self.budget = Budget()
        self.recent: deque[dict] = deque(maxlen=RECENT_DECISIONS)
        # The host's latest request, kept until a decision carries it out or declines it.
        self.request: dict | None = None
        # The active story arc (kept in the campaign so it survives a restart), and what happened to it in the
        # current decision ("started", "completed", "stopped", "failed" or ""), reported back to the game.
        self.arc_path = arc_path
        self.arc = Arc.load(arc_path) if arc_path else None
        self.arc_event = ""
        # An arc that ended in the current decision, still reported under its title.
        self.ended_arc: Arc | None = None
        self.lock = threading.Lock()
        log_dir.mkdir(parents=True, exist_ok=True)
        self.log_path = log_dir / f"decisions-{datetime.now():%Y%m%d-%H%M%S}.jsonl"

    def decide(self, state: dict) -> Decision:
        with self.lock:
            started = time.monotonic()
            self.arc_event = ""
            self.ended_arc = None
            # The game sends a request once; it replaces any earlier one still pending.
            state = dict(state)
            request = state.pop("request", None)
            if isinstance(request, str) and request.strip():
                self.request = {"text": request.strip()[:MAX_REQUEST_CHARS], "since_game_time": state.get("time")}
                log.info("Request from the host: %s", self.request["text"])
            arc_request = state.pop("arc_request", None)
            if isinstance(arc_request, dict):
                self._handle_arc_request(arc_request, state)

            personality = self._personality(state)
            self.last_personality = personality
            busy = self.request is not None or self.arc is not None
            if self.pacer.should_skip(state, has_request=busy):
                # Not added to the recent decisions Claude sees: it didn't make this one.
                decision = Decision.wait("skipped: nothing important changed since Claude last looked")
                self._record(state, request, personality, None, decision, None, time.monotonic() - started)
                return decision

            proposed, usage = self._ask(state, personality)
            self.pacer.asked(state)
            decision = check(proposed, state, self.budget)
            if self.request and decision.request_done:
                log.info("Request done: %s", self.request["text"])
                self.request = None
            if self.arc and decision.arc_beat_done:
                self._advance_arc(state, decision)
            self.recent.append({"game_time": state.get("time"), **decision.model_dump(exclude_none=True)})
            self._record(state, request, personality, proposed, decision, usage, time.monotonic() - started)
            return decision

    def reply(self, state: dict) -> dict:
        """The decision as sent to the game, with the style it used (if the game asked for a style the companion
        doesn't know, the game sees the difference and says so) and the story arc's progress."""
        decision = self.decide(state)
        return {**decision.model_dump(), "personality": self.last_personality, "arc": self._arc_summary()}

    def _handle_arc_request(self, arc_request: dict, state: dict) -> None:
        if arc_request.get("stop"):
            if self.arc:
                log.info("Story arc stopped: %s", self.arc.title)
                self.arc_event = "stopped"
                self.ended_arc = self.arc
            self._set_arc(None)
            return
        asked_for = str(arc_request.get("text") or "").strip()[:MAX_REQUEST_CHARS]
        log.info("Planning a story arc: %s", asked_for or "(director's choice)")
        user = "\n".join([
            "The host's idea for the arc:",
            asked_for or "none: choose one that fits the session",
            "",
            "Recent decisions, oldest first:",
            json.dumps(list(self.recent), sort_keys=True),
            "",
            "Current state:",
            json.dumps(state, sort_keys=True),
        ])
        system = [ARC_PROMPT] + ([f"Campaign story so far, from earlier sessions:\n{self.story}"] if self.story else [])
        answer = self.backend.structured(system, user, ARC_SCHEMA, ARC_EFFORT, ARC_TIMEOUT_SECONDS, cache=False)
        try:
            plan = ArcPlan.model_validate(answer.data) if answer.data is not None else None
        except ValidationError as e:
            log.error("Arc plan does not match the schema: %s", e)
            plan = None
        if plan is None:
            log.error("No story arc planned: %s", answer.error or "malformed plan")
            self.arc_event = "failed"
            return
        # A new arc replaces any running one.
        self._set_arc(Arc.start(plan, asked_for, state.get("time", 0)))
        self.arc_event = "started"
        log.info("Story arc started: %s (%d beats)", plan.title, len(plan.beats))

    def _advance_arc(self, state: dict, decision: Decision) -> None:
        finished = self.arc.advance(state.get("time", 0), decision.reason)
        log.info("Story arc beat %d of %d done: %s", self.arc.current, len(self.arc.beats), self.arc.title)
        if finished:
            log.info("Story arc completed: %s", self.arc.title)
            self.arc_event = "completed"
            self.ended_arc = self.arc
            self._set_arc(None)
        else:
            self._set_arc(self.arc)

    def _set_arc(self, arc: Arc | None) -> None:
        """Makes `arc` the active one and saves it, or ends the active one."""
        self.arc = arc
        if self.arc_path:
            if arc:
                arc.save(self.arc_path)
            else:
                self.arc_path.unlink(missing_ok=True)

    def _personality(self, state: dict) -> str:
        chosen = state.get("director", {}).get("personality") or self.personality
        if chosen not in self.styles:
            log.warning("Unknown personality %r; using %s", chosen, self.personality)
            return self.personality
        return chosen

    def _ask(self, state: dict, personality: str) -> tuple[Decision, dict | None]:
        answer = self.backend.structured(
            self._system(personality), self._message(state), DECISION_SCHEMA, self.effort, DECISION_TIMEOUT_SECONDS
        )
        if answer.data is None:
            return Decision.wait(answer.error or "no answer"), answer.usage
        try:
            return Decision.model_validate(answer.data), answer.usage
        except ValidationError as e:
            log.error("Decision does not match the schema: %s", e)
            return Decision.wait("malformed decision"), answer.usage

    def _system(self, personality: str) -> list[str]:
        """The parts that stay the same for the whole session (so the API backend can cache them): the rules
        with the style, and the campaign's story so far."""
        blocks = [system_prompt(self.styles[personality])]
        if self.story:
            blocks.append(f"Campaign story so far, from earlier sessions:\n{self.story}")
        return blocks

    def _message(self, state: dict) -> str:
        parts = [
            "Recent decisions, oldest first:",
            json.dumps(list(self.recent), sort_keys=True),
            "",
            "Pending player request:",
            json.dumps(self.request, sort_keys=True) if self.request else "none",
            "",
            "Active story arc:",
            self.arc.describe(state.get("time", 0)) if self.arc else "none",
            "",
            "Current state:",
            json.dumps(state, sort_keys=True),
        ]
        return "\n".join(parts)

    def _record(
        self,
        state: dict,
        request: object,
        personality: str,
        proposed: Decision | None,
        decision: Decision,
        usage: dict | None,
        seconds: float,
    ) -> None:
        entry = {
            "at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            # "skipped" when the pacer answered without asking Claude.
            "backend": self.backend.name if proposed else "skipped",
            "personality": personality,
            "seconds": round(seconds, 1),
            "state": state,
            "new_request": request,
            "pending_request": self.request,
            "arc": self._arc_record(),
            "proposed": proposed.model_dump() if proposed else None,
            "decision": decision.model_dump(),
            "usage": usage,
        }
        with self.log_path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(entry) + "\n")
        log.info("%s - %s", decision.action, decision.reason)

    def _arc_summary(self) -> dict | None:
        """The arc's title, progress and what happened to it in this decision, for the game."""
        arc = self.arc or self.ended_arc
        if arc:
            return arc.summary(self.arc_event)
        return {"title": "", "beat": 0, "beats": 0, "event": self.arc_event} if self.arc_event else None

    def _arc_record(self) -> dict | None:
        """The arc as logged with a decision: the summary plus its premise."""
        summary = self._arc_summary()
        arc = self.arc or self.ended_arc
        return {**summary, "premise": arc.plan["premise"]} if summary and arc else summary
