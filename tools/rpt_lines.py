"""Prints the AI Director's lines from Arma's latest .rpt log (self-test results, decisions, errors).

    python tools/rpt_lines.py [--tests] [--rpt PATH]

--tests prints only the self-test lines. Script errors in the director's functions are included either way.
"""

import argparse
import os
import re
from pathlib import Path

RPT_DIR = Path(os.environ.get("LOCALAPPDATA", "")) / "Arma 3"
DIRECTOR = re.compile(r'"\[AI Director\] (.*)"$')


def latest_rpt() -> Path:
    rpts = sorted(RPT_DIR.glob("*.rpt"), key=lambda p: p.stat().st_mtime)
    if not rpts:
        raise SystemExit(f"No .rpt files in {RPT_DIR}")
    return rpts[-1]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--tests", action="store_true", help="only the self-test lines")
    parser.add_argument("--rpt", type=Path, help="log to read (default: the latest)")
    args = parser.parse_args()

    rpt = args.rpt or latest_rpt()
    print(f"# {rpt}")
    lines = rpt.read_text(encoding="utf-8", errors="replace").splitlines()
    for i, line in enumerate(lines):
        if match := DIRECTOR.search(line):
            text = match.group(1)
            if not args.tests or text.startswith("TEST "):
                print(f"{line[:8]} {text}")
        elif "ai_director" in line and "Error" in line:
            # Script errors print the expression first and the file a few lines later.
            print("\n".join(lines[max(0, i - 4):i + 1]))


if __name__ == "__main__":
    main()
