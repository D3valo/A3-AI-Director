"""The director's styles: the built-in ones, plus any in companion/personalities.toml.

The file adds styles or replaces built-in ones (see personalities.example.toml):

    [grimdark]
    style = "Grimdark: ..."

A style's text is appended to the director's system prompt for the whole session.
"""

from __future__ import annotations

import re
import tomllib
from pathlib import Path

BUILT_IN: dict[str, str] = {
    "balanced": "Balanced: follow the guidance above as written.",
    "cinematic": (
        "Cinematic: you are telling a story. Favour atmosphere, set pieces and slow-building tension: narrate "
        "more often, let threats announce themselves before they arrive, and build towards climaxes rather "
        "than wearing the players down. Spectacle over attrition."
    ),
    "merciless": (
        "Merciless: the occupiers are competent and relentless. Act more often, answer every rebel success "
        "with a reply, and keep the pressure on a strong squad; rewards and intel are rare. Still never pile "
        "on a squad that is already broken; hard, not hopeless."
    ),
    "supportive": (
        "Supportive: the players are few or still learning. Keep fights small and readable, help often with "
        "intel, rewards and missions, and give them time to recover between fights. Pressure comes rarely, "
        "in fireteams rather than squads."
    ),
}
DEFAULT = "balanced"
# One word, as typed after !director style.
NAME = re.compile(r"[a-z][a-z0-9_-]{0,31}")
MAX_STYLE_CHARS = 1500


def load(path: Path) -> dict[str, str]:
    """The built-in styles, updated with the file's if it exists. Raises ValueError for a malformed file."""
    styles = dict(BUILT_IN)
    if not path.exists():
        return styles
    try:
        data = tomllib.loads(path.read_text(encoding="utf-8"))
    except tomllib.TOMLDecodeError as e:
        raise ValueError(f"{path}: {e}") from e
    for name, entry in data.items():
        if not NAME.fullmatch(name):
            raise ValueError(f"{path}: style name {name!r} must be one lowercase word (letters, digits, - or _)")
        style = entry.get("style") if isinstance(entry, dict) else None
        if not isinstance(style, str) or not style.strip():
            raise ValueError(f"{path}: [{name}] needs a style = \"...\" text")
        if len(style) > MAX_STYLE_CHARS:
            raise ValueError(f"{path}: [{name}] style is longer than {MAX_STYLE_CHARS} characters")
        styles[name] = style.strip()
    return styles
