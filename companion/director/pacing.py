"""Skips the Claude call when nothing important has changed since the last state Claude saw.

Most decisions are waits, and most states during a quiet spell or a long fight look alike to a game master.
A state is reduced to a coarse fingerprint (who is alive, rough damage and enemy counts, rough position,
Antistasi's war level, aggression and missions, time of day); while it stays the same and there is no host
request pending, the director waits without asking Claude, but asks at least every `max_skip` seconds so that a
long lull is still noticed.
"""

from __future__ import annotations

import time
from collections.abc import Callable

# Enemies within 1 km, by range: none, a few, a group, many, a lot.
ENEMY_BANDS = (0, 1, 4, 8, 16)
POSITION_GRID_METRES = 300


def fingerprint(state: dict) -> tuple:
    players = tuple(sorted(
        (
            p.get("name"),
            p.get("alive", True),
            round(p.get("damage", 0) * 4),  # quarters
            _band(p.get("nearby_enemies_1km", 0)),
            p.get("group_size"),
            p.get("in_vehicle"),
            tuple(int(c // POSITION_GRID_METRES) for c in p.get("pos", [])[:2]),
        )
        for p in state.get("players", [])
    ))
    a = state.get("antistasi", {})
    antistasi = (
        a.get("war_level"),
        int(a.get("aggression_occupants", 0) // 20),
        tuple(sorted(a.get("active_missions", []))),
        a.get("big_attack_in_progress"),
    )
    return players, antistasi, _part_of_day(state.get("daytime"))


def _band(count: int) -> int:
    return sum(count >= low for low in ENEMY_BANDS)


def _part_of_day(daytime: object) -> str:
    if not isinstance(daytime, (int, float)):
        return "?"
    if 5 <= daytime < 7:
        return "dawn"
    if 7 <= daytime < 18:
        return "day"
    if 18 <= daytime < 20:
        return "dusk"
    return "night"


class Pacer:
    def __init__(self, max_skip: float, clock: Callable[[], float] = time.monotonic) -> None:
        """max_skip: the longest time in seconds without asking Claude; 0 always asks."""
        self.max_skip = max_skip
        self.clock = clock
        self.last_asked: float | None = None
        self.last_fingerprint: tuple | None = None

    def should_skip(self, state: dict, has_request: bool) -> bool:
        if self.max_skip <= 0 or has_request or self.last_asked is None:
            return False
        if self.clock() - self.last_asked >= self.max_skip:
            return False
        return fingerprint(state) == self.last_fingerprint

    def asked(self, state: dict) -> None:
        self.last_asked = self.clock()
        self.last_fingerprint = fingerprint(state)
