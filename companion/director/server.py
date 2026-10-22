"""Loopback HTTP server the extension posts game states to."""

from __future__ import annotations

import json
import logging
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from .decider import Director

log = logging.getLogger(__name__)

MAX_STATE_BYTES = 256 * 1024


def serve(director: Director, port: int) -> None:
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:
            if self.path == "/health":
                self._reply(200, {"ok": True, "backend": director.backend.name})
            else:
                self._reply(404, {"error": "not found"})

        def do_POST(self) -> None:
            if self.path != "/decide":
                self._reply(404, {"error": "not found"})
                return
            length = int(self.headers.get("Content-Length", 0))
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
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    log.info("Listening on http://127.0.0.1:%d (backend %s, log %s)", port, director.backend.name, director.log_path)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
