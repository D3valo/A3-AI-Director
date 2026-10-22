"""AI Director companion.

    python -m director serve                      serve the extension on 127.0.0.1; on Ctrl+C, write the
                                                  session's after-action report and update the story
    python -m director decide samples/state.json  one decision for a saved state, printed as JSON
    python -m director report [--log PATH]        write the report and story for a session (default: the
                                                  campaign's latest), e.g. if the companion was closed

Each campaign (--campaign, default "default") keeps its logs, reports and story so far in
campaigns/<name>/. Styles (--personality): balanced, cinematic, merciless, supportive, plus any in
personalities.toml; serve remembers the style for the campaign, so later sessions can leave it out.
While nothing important changes, serve waits without asking Claude for up to --max-skip seconds.
Backends (--backend): claude-code (default) runs the local `claude` CLI on your
Claude subscription, for your own games only; api uses an Anthropic API key; offline always waits.
"""

import argparse
import json
import logging
from pathlib import Path

from . import personalities
from .backends import make_backend
from .campaign import Campaign
from .decider import DEFAULT_MAX_SKIP_SECONDS, Director
from .server import serve

DEFAULT_PORT = 47800  # must match DEFAULT_URL in extension/src/lib.rs
COMPANION_DIR = Path(__file__).resolve().parent.parent
CAMPAIGNS_DIR = COMPANION_DIR / "campaigns"
PERSONALITIES_FILE = COMPANION_DIR / "personalities.toml"


def main() -> None:
    parser = argparse.ArgumentParser(prog="director", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--backend", choices=["claude-code", "api", "offline"], default="claude-code")
    parser.add_argument("--effort", choices=["low", "medium", "high"], default="low", help="for decisions")
    parser.add_argument(
        "--personality",
        help="the director's style (default: the campaign's, else balanced); !director style changes it in game",
    )
    parser.add_argument("--personalities", type=Path, default=PERSONALITIES_FILE, help="file with custom styles")
    parser.add_argument("--campaign", default="default")
    parser.add_argument("--campaigns-dir", type=Path, default=CAMPAIGNS_DIR, help="where campaigns are kept")
    commands = parser.add_subparsers(dest="command", required=True)
    serve_cmd = commands.add_parser("serve")
    serve_cmd.add_argument("--port", type=int, default=DEFAULT_PORT)
    serve_cmd.add_argument("--no-report", action="store_true", help="don't write a report when stopped")
    serve_cmd.add_argument(
        "--max-skip", type=float, default=DEFAULT_MAX_SKIP_SECONDS,
        help="while nothing important changes, wait without asking Claude for up to this many seconds (0: always ask)",
    )
    decide_cmd = commands.add_parser("decide")
    decide_cmd.add_argument("state", type=Path)
    report_cmd = commands.add_parser("report")
    report_cmd.add_argument("--log", type=Path, help="decision log (default: the campaign's latest)")
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    campaign = Campaign(args.campaigns_dir, args.campaign)
    try:
        styles = personalities.load(args.personalities)
    except ValueError as e:
        raise SystemExit(f"Bad personalities file: {e}")
    personality = campaign.choose_personality(args.personality, styles, remember=args.command == "serve")
    backend = make_backend(args.backend)

    match args.command:
        case "serve":
            director = Director(
                backend, campaign.logs_dir, args.effort, campaign.story(), personality, args.max_skip, styles
            )
            serve(director, args.port)
            if not args.no_report and director.log_path.exists():
                print("Writing the session report; press Ctrl+C again to skip.")
                try:
                    campaign.write_report(director.log_path, backend)
                except KeyboardInterrupt:
                    print("Skipped. Run `python -m director report` later to write it.")
        case "decide":
            director = Director(
                backend, campaign.logs_dir, args.effort, campaign.story(), personality, styles=styles
            )
            state = json.loads(args.state.read_text(encoding="utf-8"))
            print(director.decide(state).model_dump_json(indent=2))
        case "report":
            log_path = args.log or campaign.latest_log()
            if log_path is None:
                raise SystemExit(f"No decision logs in {campaign.logs_dir}")
            campaign.write_report(log_path, backend)



main()
