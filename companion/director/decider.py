"""Turns a game state into a checked decision, using one of the backends in backends.py."""

from __future__ import annotations

import json
import logging
import threading
import time
from collections import deque
from datetime import datetime, timezone
from pathlib import Path

from .backends import Backend
from .catalogue import MAX_REQUEST_CHARS, Budget, Decision, check

log = logging.getLogger(__name__)

RECENT_DECISIONS = 5


class Director:
    def __init__(self, backend: Backend, log_dir: Path) -> None:
        self.backend = backend
        self.budget = Budget()
        self.recent: deque[dict] = deque(maxlen=RECENT_DECISIONS)
        # The host's latest request, kept until a decision carries it out or declines it.
        self.request: dict | None = None
        self.lock = threading.Lock()
        log_dir.mkdir(parents=True, exist_ok=True)
        self.log_path = log_dir / f"decisions-{datetime.now():%Y%m%d-%H%M%S}.jsonl"

    def decide(self, state: dict) -> Decision:
        with self.lock:
            started = time.monotonic()
            # The game sends a request once; it replaces any earlier one still pending.
            state = dict(state)
            request = state.pop("request", None)
            if isinstance(request, str) and request.strip():
                self.request = {"text": request.strip()[:MAX_REQUEST_CHARS], "since_game_time": state.get("time")}
                log.info("Request from the host: %s", self.request["text"])

            proposed, usage = self.backend.ask(self._message(state))
            decision = check(proposed, state, self.budget)
            if self.request and decision.request_done:
                log.info("Request done: %s", self.request["text"])
                self.request = None
            self.recent.append({"game_time": state.get("time"), **decision.model_dump(exclude_none=True)})
            self._record(state, request, proposed, decision, usage, time.monotonic() - started)
            return decision

    def _message(self, state: dict) -> str:
        parts = [
            "Recent decisions, oldest first:",
            json.dumps(list(self.recent), sort_keys=True),
            "",
            "Pending player request:",
            json.dumps(self.request, sort_keys=True) if self.request else "none",
            "",
            "Current state:",
            json.dumps(state, sort_keys=True),
        ]
        return "\n".join(parts)

    def _record(
        self, state: dict, request: object, proposed: Decision, decision: Decision, usage: dict | None, seconds: float
    ) -> None:
        entry = {
            "at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "backend": self.backend.name,
            "seconds": round(seconds, 1),
            "state": state,
            "new_request": request,
            "pending_request": self.request,
            "proposed": proposed.model_dump(),
            "decision": decision.model_dump(),
            "usage": usage,
        }
        with self.log_path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(entry) + "\n")
        log.info("%s - %s", decision.action, decision.reason)
