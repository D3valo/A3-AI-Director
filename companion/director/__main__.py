"""AI Director companion.

    python -m director serve                      serve the extension on 127.0.0.1
    python -m director decide samples/state.json  one decision for a saved state, printed as JSON

Backends (--backend): claude-code (default) runs the local `claude` CLI on your Claude subscription,
for your own games only; api uses an Anthropic API key; offline always waits.
"""

import argparse
import json
import logging
from pathlib import Path

from .backends import make_backend
from .decider import Director
from .server import serve

DEFAULT_PORT = 47800  # must match DEFAULT_URL in extension/src/lib.rs


def main() -> None:
    parser = argparse.ArgumentParser(prog="director", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--backend", choices=["claude-code", "api", "offline"], default="claude-code")
    parser.add_argument("--effort", choices=["low", "medium", "high"], default="low")
    parser.add_argument("--log-dir", type=Path, default=Path(__file__).resolve().parent.parent / "logs")
    commands = parser.add_subparsers(dest="command", required=True)
    serve_cmd = commands.add_parser("serve")
    serve_cmd.add_argument("--port", type=int, default=DEFAULT_PORT)
    decide_cmd = commands.add_parser("decide")
    decide_cmd.add_argument("state", type=Path)
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    director = Director(make_backend(args.backend, args.effort), args.log_dir)
    if args.command == "serve":
        serve(director, args.port)
    else:
        state = json.loads(args.state.read_text(encoding="utf-8"))
        print(director.decide(state).model_dump_json(indent=2))


main()
