import tempfile
import unittest
from pathlib import Path

from director import personalities
from director.campaign import Campaign, read_log, session_digest
from director.catalogue import Decision
from director.decider import Director
from director.prompt import system_prompt
from tests.test_decider import STATE, ScriptedBackend


class Recorder(ScriptedBackend):
    """A scripted backend that also records the system prompts it was given."""

    def __init__(self, *answers) -> None:
        super().__init__(*answers)
        self.systems: list[str] = []

    def structured(self, system, user, schema, effort, timeout):
        self.systems.append(system)
        return super().structured(system, user, schema, effort, timeout)


def write(text: str) -> Path:
    path = Path(tempfile.mkdtemp()) / "personalities.toml"
    path.write_text(text, encoding="utf-8")
    return path


class LoadTests(unittest.TestCase):
    def test_built_ins_without_a_file(self) -> None:
        self.assertEqual(personalities.load(Path(tempfile.mkdtemp()) / "none.toml"), personalities.BUILT_IN)

    def test_file_adds_and_replaces(self) -> None:
        styles = personalities.load(write('[grimdark]\nstyle = "Bleak."\n[balanced]\nstyle = "Even."\n'))
        self.assertEqual(styles["grimdark"], "Bleak.")
        self.assertEqual(styles["balanced"], "Even.")
        self.assertEqual(styles["cinematic"], personalities.BUILT_IN["cinematic"])

    def test_example_file_loads(self) -> None:
        example = Path(__file__).resolve().parent.parent / "personalities.example.toml"
        self.assertIn("grimdark", personalities.load(example))

    def test_malformed_files(self) -> None:
        for text in ('[Grim Dark]\nstyle = "x"\n', '[grim]\ntext = "x"\n', '[grim]\nstyle = ""\n', "[grim\n"):
            with self.assertRaises(ValueError, msg=text):
                personalities.load(write(text))


class DirectorStyleTests(unittest.TestCase):
    def setUp(self) -> None:
        self.log_dir = Path(tempfile.mkdtemp())
        self.styles = {**personalities.BUILT_IN, "grimdark": "Bleak."}

    def test_game_chooses_and_reply_reports_the_style(self) -> None:
        backend = Recorder(Decision.wait("a"), Decision.wait("b"), Decision.wait("c"))
        director = Director(backend, self.log_dir, personality="cinematic", styles=self.styles)
        self.assertEqual(director.reply(STATE)["personality"], "cinematic")
        self.assertEqual(director.reply({**STATE, "director": {"personality": "grimdark"}})["personality"], "grimdark")
        # Unknown: falls back, and the reply tells the game which style it got instead.
        self.assertEqual(director.reply({**STATE, "director": {"personality": "nonsense"}})["personality"], "cinematic")
        self.assertEqual(backend.systems, [system_prompt(self.styles["cinematic"]), system_prompt("Bleak."),
                                           system_prompt(self.styles["cinematic"])])


class CampaignStyleTests(unittest.TestCase):
    def setUp(self) -> None:
        self.campaign = Campaign(Path(tempfile.mkdtemp()), "test")
        self.styles = {**personalities.BUILT_IN, "grimdark": "Bleak."}

    def test_default_then_remembered(self) -> None:
        self.assertEqual(self.campaign.choose_personality(None, self.styles, remember=True), "balanced")
        self.assertEqual(self.campaign.choose_personality("grimdark", self.styles, remember=True), "grimdark")
        self.assertEqual(self.campaign.choose_personality(None, self.styles, remember=True), "grimdark")

    def test_not_remembered_outside_serve(self) -> None:
        self.campaign.choose_personality("merciless", self.styles, remember=False)
        self.assertEqual(self.campaign.choose_personality(None, self.styles, remember=True), "balanced")

    def test_unknown_styles(self) -> None:
        with self.assertRaises(SystemExit):
            self.campaign.choose_personality("nonsense", self.styles, remember=True)
        self.campaign.update_settings(personality="deleted-style")
        self.assertEqual(self.campaign.choose_personality(None, self.styles, remember=True), "balanced")

    def test_digest_names_the_style_and_changes(self) -> None:
        backend = ScriptedBackend(Decision.wait("a"), Decision.wait("b"))
        director = Director(backend, self.campaign.logs_dir, personality="cinematic")
        director.decide({**STATE, "time": 60})
        director.decide({**STATE, "time": 120, "director": {"personality": "merciless"}})
        digest = session_digest(read_log(director.log_path))
        self.assertIn("Director style: cinematic", digest)
        self.assertIn("- 0:02 style changed to merciless", digest)


if __name__ == "__main__":
    unittest.main()
