import json
import unittest

from director.backends import parse_claude_code_output

ANSWER = {"action": "narrate", "reason": "lull"}


def output(**fields) -> str:
    return json.dumps({"type": "result", "subtype": "success", "is_error": False, "total_cost_usd": 0.01, **fields})


class ClaudeCodeOutputTests(unittest.TestCase):
    def test_structured_output(self) -> None:
        answer = parse_claude_code_output(0, output(structured_output=ANSWER), "")
        self.assertEqual(answer.data, ANSWER)
        self.assertEqual(answer.usage["total_cost_usd"], 0.01)

    def test_missing_structured_output(self) -> None:
        answer = parse_claude_code_output(0, output(result="I won't do that."), "")
        self.assertIsNone(answer.data)
        self.assertIn("no answer", answer.error)

    def test_error_result(self) -> None:
        answer = parse_claude_code_output(1, output(is_error=True, subtype="error_during_execution"), "")
        self.assertIsNone(answer.data)
        self.assertIn("error_during_execution", answer.error)

    def test_not_json(self) -> None:
        answer = parse_claude_code_output(1, "", "Not logged in")
        self.assertIsNone(answer.data)
        self.assertIsNone(answer.usage)


if __name__ == "__main__":
    unittest.main()
