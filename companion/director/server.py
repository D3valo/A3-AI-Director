"""Loopback HTTP server the extension posts game states to.

Only the extension may use it. Binding to 127.0.0.1 keeps the network out, but a web page open in a browser on the
same PC can still send requests to loopback addresses. So every request must also look like the extension's: a Host
header naming the loopback address and this port (which stops DNS rebinding, where a hostile domain resolves to
127.0.0.1), no Origin header (browsers add one to cross-site requests; the extension never does), and for a state, a
JSON content type (which a page can only send after a CORS preflight that this server never answers).
"""

from __future__ import annotations

import json
import logging
from email.message import Message
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from .decider import Director

log = logging.getLogger(__name__)

MAX_STATE_BYTES = 256 * 1024
LOOPBACK_HOSTS = ("127.0.0.1", "localhost")


def refusal(headers: Message, port: int, needs_json: bool) -> str | None:
    """Why a request doesn't come from the extension, or None if it may."""
    if headers.get("Host", "").lower() not in {f"{host}:{port}" for host in LOOPBACK_HOSTS}:
        return "unexpected Host"
    if "Origin" in headers:
        return "browser requests are not accepted"
    if needs_json and headers.get_content_type() != "application/json":
        return "Content-Type must be application/json"
    return None


def make_server(director: Director, port: int) -> ThreadingHTTPServer:
    """The server on 127.0.0.1:port (0 picks a free port; see server_address)."""

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:
            if self._refused(needs_json=False):
                return
            if self.path == "/health":
                self._reply(200, {"ok": True, "backend": director.backend.name})
            else:
                self._reply(404, {"error": "not found"})

        def do_POST(self) -> None:
            if self._refused(needs_json=True):
                return
            if self.path != "/decide":
                self._reply(404, {"error": "not found"})
                return
            try:
                length = int(self.headers.get("Content-Length", 0))
            except ValueError:
                length = 0
            if not 0 < length <= MAX_STATE_BYTES:
                self._reply(413, {"error": "state missing or too large"})
                return
            try:
                state = json.loads(self.rfile.read(length))
            except json.JSONDecodeError as e:
                self._reply(400, {"error": f"invalid JSON: {e}"})
                return
            if not isinstance(state, dict):
                self._reply(400, {"error": "state must be a JSON object"})
                return
            self._reply(200, director.reply(state))

        def _refused(self, needs_json: bool) -> bool:
            problem = refusal(self.headers, self.server.server_address[1], needs_json)
            if problem:
                log.warning("Refused a %s %s from outside the game: %s", self.command, self.path, problem)
                self._reply(403, {"error": problem})
            return problem is not None

        def _reply(self, status: int, body: dict) -> None:
            data = json.dumps(body).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def log_message(self, format: str, *args) -> None:
            log.debug(format, *args)

    # Loopback only: the companion holds the API key and must not be reachable from the network.
    return ThreadingHTTPServer(("127.0.0.1", port), Handler)


def serve(director: Director, port: int) -> None:
    server = make_server(director, port)
    log.info(
        "Listening on http://127.0.0.1:%d (backend %s, narrative %s, log %s)",
        port, director.backend.name, "on" if director.narrative else "off", director.log_path,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
