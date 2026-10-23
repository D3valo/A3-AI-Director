"""Narrative off (--no-narrative): only decisions that change the game."""
import json
import tempfile
import unittest
from pathlib import Path

from director import personalities
from director.arcs import Arc, ArcPlan
from director.catalogue import ACTIONS, DECISION_SCHEMA, Budget, check, decision_schema
from director.decider import Director
from director.prompt import system_prompt
from tests.test_arcs import PLAN
from tests.test_decider import STATE, ScriptedBackend
from tests.test_session_fixes import act

STYLE = personalities.BUILT_IN[personalities.DEFAULT]


class SchemaRecordingBackend(ScriptedBackend):
    def structured(self, system, user, schema, effort, timeout, cache=True):
        self.schemas = getattr(self, "schemas", []) + [schema]
        return super().structured(system, user, schema, effort, timeout, cache)


class NarrativeOffTests(unittest.TestCase):
    def setUp(self) -> None:
        folder = Path(tempfile.mkdtemp())
        self.log_dir = folder / "logs"
        self.arc_path = folder / "arc.json"

    def test_schema_has_no_narrate(self) -> None:
        self.assertIs(decision_schema(), DECISION_SCHEMA)
        actions = decision_schema(narrative=False)["properties"]["action"]["enum"]
        self.assertNotIn("narrate", actions)
        self.assertEqual(set(actions) | {"narrate"}, set(ACTIONS))
        self.assertIn("narrate", DECISION_SCHEMA["properties"]["action"]["enum"])

    def test_prompt_leaves_out_the_story(self) -> None:
        prompt = system_prompt(STYLE, narrative=False)
        for text in ("- narrate (message)", "Campaign memory:", "Story arcs:", "optional message", "narration"):
            self.assertNotIn(text, prompt)
        self.assertIn("Gameplay only:", prompt)
        self.assertIn("Player requests:", prompt)
        self.assertIn("- informant (target_player):", prompt)
        narrative = system_prompt(STYLE)
        for text in ("- narrate (message)", "Campaign memory:", "Story arcs:", "narration and informant lines"):
            self.assertIn(text, narrative)
        self.assertNotIn("Gameplay only:", narrative)

    def test_check_rejects_narrate_and_drops_informant_lines(self) -> None:
        budget = Budget()
        rejected = check(act("narrate", message="Static."), STATE, budget, narrative=False)
        self.assertEqual(rejected.action, "wait")
        self.assertIn("narrative is off", rejected.reason)
        self.assertEqual(budget.cooling_down(), {})
        informant = check(act("informant", target_player="Alpha 1-1", message="They went north."), STATE, budget,
                          narrative=False)
        self.assertEqual((informant.action, informant.message), ("informant", None))
        self.assertEqual(check(act("narrate", message="Static."), STATE, Budget()).action, "narrate")

    def test_director_without_story_or_arcs(self) -> None:
        Arc.start(ArcPlan.model_validate(PLAN), "", 0).save(self.arc_path)
        backend = SchemaRecordingBackend(act("wait"), act("wait"))
        director = Director(backend, self.log_dir, story="The cell hit a convoy.", arc_path=self.arc_path,
                            narrative=False)
        director.decide(STATE)
        reply = director.reply({**STATE, "arc_request": {"text": "a manhunt"}})
        # The arc request costs no Claude call, and the saved arc is kept for a session with narrative.
        self.assertEqual(len(backend.messages), 2)
        self.assertEqual(reply["arc"], {"title": "", "beat": 0, "beats": 0, "event": "off"})
        self.assertTrue(self.arc_path.exists())
        self.assertEqual(len(backend.systems[0]), 1)
        self.assertNotIn("Active story arc:", backend.messages[0])
        self.assertEqual(backend.schemas[0], decision_schema(narrative=False))
        logged = [json.loads(line) for line in director.log_path.read_text(encoding="utf-8").splitlines()]
        self.assertEqual(len(logged), 2)


if __name__ == "__main__":
    unittest.main()
