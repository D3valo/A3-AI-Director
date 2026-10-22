import json
import unittest

from director.backends import parse_claude_code_output

DECISION = {"action": "narrate", "reason": "lull", "message": "Static on the radio.", "target_player": None, "strength": None, "request_done": False}


def output(**fields) -> str:
    return json.dumps({"type": "result", "subtype": "success", "is_error": False, "total_cost_usd": 0.01, **fields})


class ClaudeCodeOutputTests(unittest.TestCase):
    def test_structured_output(self) -> None:
        decision, usage = parse_claude_code_output(0, output(structured_output=DECISION), "")
        self.assertEqual(decision.action, "narrate")
        self.assertEqual(usage["total_cost_usd"], 0.01)

    def test_missing_structured_output_waits(self) -> None:
        decision, _ = parse_claude_code_output(0, output(result="I won't do that."), "")
        self.assertEqual(decision.action, "wait")

    def test_error_result_waits(self) -> None:
        decision, _ = parse_claude_code_output(1, output(is_error=True, subtype="error_during_execution"), "")
        self.assertEqual(decision.action, "wait")
        self.assertIn("error_during_execution", decision.reason)

    def test_not_json_waits(self) -> None:
        decision, usage = parse_claude_code_output(1, "", "Not logged in")
        self.assertEqual(decision.action, "wait")
        self.assertIsNone(usage)

    def test_schema_mismatch_waits(self) -> None:
        decision, _ = parse_claude_code_output(0, output(structured_output={"action": "nuke"}), "")
        self.assertEqual(decision.action, "wait")


if __name__ == "__main__":
    unittest.main()
