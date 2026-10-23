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
from .catalogue import MAX_REQUEST_CHARS, Budget, Decision, check, decision_schema
from .pacing import Pacer, has_news
from .prompt import ARC_PROMPT, system_prompt

log = logging.getLogger(__name__)

RECENT_DECISIONS = 5
DECISION_TIMEOUT_SECONDS = 120
ARC_EFFORT = "medium"
ARC_TIMEOUT_SECONDS = 180
DEFAULT_MAX_SKIP_SECONDS = 300


def _minute(state: dict) -> int:
    """Game time in whole minutes, the unit of everything Claude sees."""
    return round(state.get("time", 0) / 60)


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
        narrative: bool = True,
    ) -> None:
        self.backend = backend
        self.effort = effort
        # False (--no-narrative): only decisions that change the game. No narrate, no informant lines, no campaign
        # story and no story arcs; the arc in arc.json is left alone for a later session with narrative.
        self.narrative = narrative
        # The campaign's story so far, read once per session.
        self.story = story if narrative else None
        # The session's style, unless the game asks for another (!director style ...).
        self.styles = styles if styles is not None else dict(personalities.BUILT_IN)
        self.personality = personality
        # The style the last decision used, reported back to the game.
        self.last_personality = personality
        self.pacer = Pacer(max_skip)
        # Events from states the pacer answered without Claude, passed on with the next one Claude sees.
        self.unseen_events: list = []
        self.budget = Budget()
        self.recent: deque[dict] = deque(maxlen=RECENT_DECISIONS)
        # The host's latest request, kept until a decision carries it out or declines it, and what the host should
        # hear about it after the current decision (see _request_news).
        self.request: dict | None = None
        self.request_news = ""
        # The active story arc (kept in the campaign so it survives a restart), and what happened to it in the
        # current decision ("started", "completed", "stopped", "failed" or ""), reported back to the game.
        self.arc_path = arc_path
        self.arc = Arc.load(arc_path) if arc_path and narrative else None
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
            self.request_news = ""
            # The game sends a request once; it replaces any earlier one still pending.
            state = dict(state)
            request = state.pop("request", None)
            if isinstance(request, str) and request.strip():
                self.request = {"text": request.strip()[:MAX_REQUEST_CHARS], "since_minute": _minute(state)}
                log.info("Request from the host: %s", self.request["text"])
            # The self-test's state must reach Claude, never the pacer.
            self_test = bool(state.pop("self_test", False))
            arc_request = state.pop("arc_request", None)
            if isinstance(arc_request, dict):
                self._handle_arc_request(arc_request, state)

            personality = self._personality(state)
            self.last_personality = personality
            busy = self.request is not None or self.arc is not None or has_news(state) or self_test
            if self.pacer.should_skip(state, has_request=busy):
                # Not added to the recent decisions Claude sees: it didn't make this one. Its events (kill
                # tallies) go with the next state Claude does see.
                self.unseen_events += state.get("events", [])
                decision = Decision.wait("skipped: nothing important changed since Claude last looked")
                self._record(state, request, personality, None, decision, None, time.monotonic() - started)
                return decision

            state["events"] = self.unseen_events + state.get("events", [])
            self.unseen_events = []
            proposed, usage = self._ask(state, personality)
            self.pacer.asked(state)
            decision = check(
                proposed, state, self.budget, host_request=self.request is not None, narrative=self.narrative
            )
            self.request_news = self._request_news(request, proposed, decision)
            if self.request and decision.request_done:
                log.info("Request done: %s", self.request["text"])
                self.request = None
            if self.arc and decision.arc_beat_done:
                self._advance_arc(state, decision)
            self.recent.append({"minute": _minute(state), **decision.model_dump(exclude_none=True)})
            self._record(state, request, personality, proposed, decision, usage, time.monotonic() - started)
            return decision

    def reply(self, state: dict) -> dict:
        """The decision as sent to the game, with the style it used (if the game asked for a style the companion
        doesn't know, the game sees the difference and says so) and the story arc's progress."""
        decision = self.decide(state)
        return {
            **decision.model_dump(), "personality": self.last_personality, "arc": self._arc_summary(),
            "request_news": self.request_news,
        }

    def _request_news(self, new_request: object, proposed: Decision, decision: Decision) -> str:
        """What the host who sent the pending request should hear: when it's carried out or turned down, and
        on the first decision after it arrives (taken on, or why it has to wait). Nothing in between, so the
        chat isn't repeated every decision."""
        if not self.request:
            return ""
        if decision.request_done:
            if decision.action == "wait":
                return f"can't be done: {decision.reason}"
            return f"the director chose {decision.action}: {decision.reason}"
        if new_request:
            if proposed.action != decision.action:
                return f"waiting: {proposed.action} is not possible yet ({decision.reason.split(' (')[0]})"
            return f"waiting: {decision.reason}"
        return ""

    def _handle_arc_request(self, arc_request: dict, state: dict) -> None:
        if not self.narrative:
            log.info("Story arc request ignored: narrative is off")
            self.arc_event = "off"
            return
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
            "Current state (time in minutes):",
            json.dumps({k: v for k, v in state.items() if k != "time"} | {"minute": _minute(state)}, sort_keys=True),
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
            self._system(personality), self._message(state), decision_schema(self.narrative), self.effort,
            DECISION_TIMEOUT_SECONDS,
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
        blocks = [system_prompt(self.styles[personality], self.narrative)]
        if self.story:
            blocks.append(f"Campaign story so far, from earlier sessions:\n{self.story}")
        return blocks

    def _message(self, state: dict) -> str:
        view = {k: v for k, v in state.items() if k != "time"} | {"minute": _minute(state)}
        cooling = self.budget.cooling_down()
        if not state.get("director", {}).get("cooldowns", True):
            cooldowns = "none: the host turned the cooldowns off, so every action is available now"
        else:
            cooldowns = ", ".join(
                f"{name} ({max(1, round(left / 60))})" for name, left in sorted(cooling.items())
            ) or "none"
        parts = [
            "Actions on cooldown (minutes left); every other action is available now:",
            cooldowns,
            "",
            "Recent decisions, oldest first:",
            json.dumps(list(self.recent), sort_keys=True),
            "",
            "Pending player request:",
            json.dumps(self.request, sort_keys=True) if self.request else "none",
            "",
        ]
        if self.narrative:
            parts += ["Active story arc:", self.arc.describe(state.get("time", 0)) if self.arc else "none", ""]
        parts += ["Current state:", json.dumps(view, sort_keys=True)]
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
