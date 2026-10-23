"""The companion's server answers the extension and nothing that looks like a browser."""
import http.client
import json
import tempfile
import threading
import unittest
from pathlib import Path

from director.catalogue import Decision
from director.decider import Director
from director.server import make_server
from tests.test_decider import STATE, ScriptedBackend


class ServerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.backend = ScriptedBackend(*[Decision.wait("quiet")] * 3)
        self.server = make_server(Director(self.backend, Path(tempfile.mkdtemp())), 0)
        self.port = self.server.server_address[1]
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)

    def request(self, method: str, path: str, body: str | None = None, **headers: str) -> int:
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        # http.client sends Host 127.0.0.1:<port> unless one is given, as the extension does.
        headers = {k.replace("_", "-"): v for k, v in headers.items()}
        connection.request(method, path, body=body, headers=headers)
        status = connection.getresponse().status
        connection.close()
        return status

    def post_state(self, **headers: str) -> int:
        return self.request("POST", "/decide", json.dumps(STATE), **{"Content_Type": "application/json", **headers})

    def test_the_extension_is_answered(self) -> None:
        self.assertEqual(self.post_state(), 200)
        self.assertEqual(self.post_state(Host=f"localhost:{self.port}"), 200)
        self.assertEqual(self.request("GET", "/health"), 200)
        self.assertEqual(len(self.backend.messages), 2)

    def test_browser_requests_are_refused(self) -> None:
        # A page's form or fetch: an Origin header, or a "simple" content type that skips the CORS preflight.
        self.assertEqual(self.post_state(Origin="https://example.com"), 403)
        self.assertEqual(self.request("POST", "/decide", json.dumps(STATE), Content_Type="text/plain"), 403)
        # DNS rebinding: a hostile domain resolved to 127.0.0.1 keeps its own name in Host.
        self.assertEqual(self.post_state(Host=f"evil.example.com:{self.port}"), 403)
        self.assertEqual(self.request("GET", "/health", Host="evil.example.com"), 403)
        self.assertEqual(self.backend.messages, [])


if __name__ == "__main__":
    unittest.main()
