"""A campaign: one ongoing Antistasi game (or any series of sessions) with its own memory.

    campaigns/<name>/logs/decisions-*.jsonl   one decision log per companion run (session)
    campaigns/<name>/reports/<log name>.md    after-action report for each session
    campaigns/<name>/story.md                 the story so far, which the director reads every session
    campaigns/<name>/campaign.json            settings that stick to the campaign: {"personality": "cinematic"}
    campaigns/<name>/arc.json                 the story arc in progress, if any (see arcs.py)

After a session, Claude reads a digest of its decision log and writes the report and an updated story.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime
from pathlib import Path

from . import personalities
from .backends import Backend
from .prompt import REPORT_PROMPT, REPORT_SCHEMA

log = logging.getLogger(__name__)

REPORT_EFFORT = "medium"
REPORT_TIMEOUT_SECONDS = 600


class Campaign:
    def __init__(self, root: Path, name: str) -> None:
        self.name = name
        self.dir = root / name
        self.logs_dir = self.dir / "logs"
        self.reports_dir = self.dir / "reports"
        self.story_path = self.dir / "story.md"
        self.settings_path = self.dir / "campaign.json"
        self.arc_path = self.dir / "arc.json"
        for d in (self.logs_dir, self.reports_dir):
            d.mkdir(parents=True, exist_ok=True)

    def settings(self) -> dict:
        if not self.settings_path.exists():
            return {}
        return json.loads(self.settings_path.read_text(encoding="utf-8"))

    def update_settings(self, **changes: object) -> None:
        settings = {**self.settings(), **changes}
        self.settings_path.write_text(json.dumps(settings, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    def choose_personality(self, asked: str | None, styles: dict[str, str], remember: bool) -> str:
        """The style asked for (saved for the campaign if `remember`), else the campaign's, else the default."""
        if asked:
            if asked not in styles:
                raise SystemExit(f"Unknown style {asked!r}; known: {', '.join(styles)}")
            if remember:
                self.update_settings(personality=asked)
            return asked
        saved = self.settings().get("personality", personalities.DEFAULT)
        if saved not in styles:
            log.warning("Campaign style %r is no longer defined; using %s", saved, personalities.DEFAULT)
            return personalities.DEFAULT
        return saved

    def story(self) -> str | None:
        if not self.story_path.exists():
            return None
        return self.story_path.read_text(encoding="utf-8").strip() or None

    def latest_log(self) -> Path | None:
        logs = sorted(self.logs_dir.glob("decisions-*.jsonl"))
        return logs[-1] if logs else None

    def write_report(self, log_path: Path, backend: Backend) -> Path | None:
        """Writes the after-action report for one session and updates the story. Returns the report path."""
        entries = read_log(log_path)
        if not entries:
            log.info("No decisions in %s; no report written.", log_path)
            return None
        user = (
            f"Campaign: {self.name}\n"
            f"Session started: {session_name(log_path)}\n\n"
            "Story so far (before this session):\n"
            f"{self.story() or 'This is the first session.'}\n\n"
            "This session's decision log:\n"
            f"{session_digest(entries)}"
        )
        log.info("Writing the after-action report for %s ...", log_path.name)
        # Once per session, so not worth a cache write.
        answer = backend.structured(
            [REPORT_PROMPT], user, REPORT_SCHEMA, REPORT_EFFORT, REPORT_TIMEOUT_SECONDS, cache=False
        )
        if answer.data is None:
            log.error("No report written: %s", answer.error)
            return None

        report_path = self.reports_dir / f"{log_path.stem}.md"
        report_path.write_text(answer.data["report"].strip() + "\n", encoding="utf-8")
        self.story_path.write_text(answer.data["story"].strip() + "\n", encoding="utf-8")
        log.info("Report: %s. Story updated: %s", report_path, self.story_path)
        return report_path


def read_log(log_path: Path) -> list[dict]:
    with log_path.open(encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


def session_digest(entries: list[dict]) -> str:
    """A compact, readable account of a session: start and end state, host requests, and every action
    with its reason. Runs of waits are collapsed to a count, as they are most decisions."""
    first, last = entries[0], entries[-1]
    style = first.get("personality", "unrecorded")
    lines = [
        f"Real time: {first['at']} to {last['at']}, {len(entries)} decisions.",
        f"Director style: {style}",
        f"At the start: {_situation(first['state'])}",
        f"At the end: {_situation(last['state'])}",
        "",
        "Timeline (game time, then what the director did and why):",
    ]
    waits = 0
    beats_done = 0

    def note(line: str) -> None:
        nonlocal waits
        if waits:
            lines.append(f"- ({waits} waits)")
            waits = 0
        lines.append(line)

    for entry in entries:
        decision, state = entry["decision"], entry["state"]
        when = _game_time(state.get("time"))
        if entry.get("personality", style) != style:
            style = entry["personality"]
            note(f"- {when} style changed to {style}")
        if entry.get("new_request"):
            note(f"- {when} host request: {entry['new_request']}")
        arc = entry.get("arc") or {}
        match arc.get("event"):
            case "started":
                beats_done = 0
                note(f'- {when} story arc started: "{arc["title"]}" ({arc["beats"]} beats). {arc.get("premise", "")}')
            case "failed":
                note(f"- {when} a story arc was asked for but could not be planned")
        if decision["action"] == "wait" and not decision["reason"].startswith("rejected"):
            waits += 1
        else:
            details = ", ".join(
                f"{k}={v}" for k, v in decision.items()
                if k not in ("action", "reason", "request_done", "arc_beat_done") and v is not None
            )
            note(f"- {when} {decision['action']}{f' ({details})' if details else ''}: {decision['reason']}")
        if arc.get("title") and arc.get("event") != "started" and arc.get("beat", 0) - 1 > beats_done:
            beats_done = arc["beat"] - 1
            note(f'- {when} arc "{arc["title"]}": beat {beats_done} of {arc["beats"]} done')
        if arc.get("event") in ("completed", "stopped"):
            note(f'- {when} story arc {arc["event"]}: "{arc["title"]}"')
    if waits:
        lines.append(f"- ({waits} waits)")
    return "\n".join(lines)


def _situation(state: dict) -> str:
    antistasi = state.get("antistasi", {})
    players = ", ".join(
        f"{p.get('name')} ({'alive' if p.get('alive', True) else 'dead'}, damage {p.get('damage', 0)}, "
        f"{p.get('nearby_enemies_1km', '?')} enemies within 1 km)"
        for p in state.get("players", [])
    )
    parts = [f"world {state.get('world', '?')}", f"players: {players or 'none'}"]
    if antistasi.get("war_level", -1) >= 0:
        parts.append(
            "Antistasi: war level {war_level}, occupier aggression {aggression_occupants}, rebel money "
            "{rebel_money}, recruits {rebel_recruits}, active missions {active_missions}".format_map(
                {k: antistasi.get(k, "?") for k in (
                    "war_level", "aggression_occupants", "rebel_money", "rebel_recruits", "active_missions")}
            )
        )
    return "; ".join(parts)


def _game_time(seconds: object) -> str:
    if not isinstance(seconds, (int, float)):
        return "?:??"
    minutes = int(seconds) // 60
    return f"{minutes // 60}:{minutes % 60:02d}"


def session_name(log_path: Path) -> str:
    """decisions-20261022-182648 -> 2026-10-22 18:26"""
    try:
        return datetime.strptime(log_path.stem, "decisions-%Y%m%d-%H%M%S").strftime("%Y-%m-%d %H:%M")
    except ValueError:
        return log_path.stem
