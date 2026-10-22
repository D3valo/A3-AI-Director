import json
import unittest
from types import SimpleNamespace

from director.backends import CACHE_CONTROL, ApiBackend


class FakeUsage:
    def model_dump(self, exclude_none: bool = False) -> dict:
        return {"input_tokens": 10, "cache_read_input_tokens": 1500, "output_tokens": 50}


class FakeClient:
    """Records the request and answers like the SDK's beta.messages.create."""

    def __init__(self, answer: dict) -> None:
        self.answer = answer
        self.requests: list[dict] = []
        self.beta = SimpleNamespace(messages=SimpleNamespace(create=self.create))

    def with_options(self, **options) -> "FakeClient":
        return self

    def create(self, **request) -> SimpleNamespace:
        self.requests.append(request)
        return SimpleNamespace(
            usage=FakeUsage(), stop_reason="end_turn", stop_details=None,
            content=[SimpleNamespace(type="text", text=json.dumps(self.answer))],
        )


class ApiBackendTests(unittest.TestCase):
    def test_cache_breakpoint_on_the_last_system_block(self) -> None:
        client = FakeClient({"ok": True})
        answer = ApiBackend(client).structured(["rules", "story"], "state", {"type": "object"}, "low", 30)
        system = client.requests[0]["system"]
        self.assertEqual(system[0], {"type": "text", "text": "rules"})
        self.assertEqual(system[1], {"type": "text", "text": "story", "cache_control": CACHE_CONTROL})
        self.assertNotIn("cache_control", client.requests[0])  # no top-level auto-caching of the user message
        self.assertEqual(answer.data, {"ok": True})
        self.assertEqual(answer.usage["cache_read_input_tokens"], 1500)

    def test_no_cache_when_asked(self) -> None:
        client = FakeClient({"ok": True})
        ApiBackend(client).structured(["report rules"], "log", {"type": "object"}, "medium", 30, cache=False)
        self.assertEqual(client.requests[0]["system"], [{"type": "text", "text": "report rules"}])

    def test_request_shape(self) -> None:
        client = FakeClient({"ok": True})
        ApiBackend(client).structured(["rules"], "state", {"type": "object"}, "low", 30)
        request = client.requests[0]
        self.assertEqual(request["model"], "claude-opus-5-5")
        self.assertEqual(request["fallbacks"], "default")
        self.assertEqual(request["output_config"]["effort"], "low")
        self.assertEqual(request["messages"], [{"role": "user", "content": "state"}])


if __name__ == "__main__":
    unittest.main()
