"""Ways of asking Claude for a decision. Each backend takes the user message (recent decisions and the
game state) and returns the proposed decision plus usage details for the log; failures become a `wait`.

- ClaudeCodeBackend runs the local `claude` CLI in print mode, on the Claude subscription it is logged
  in with. For personal use only: never use it to serve other people's requests.
- ApiBackend calls the Claude API with an API key (ANTHROPIC_API_KEY or an `ant auth login` profile).
- OfflineBackend always waits, for testing the plumbing.
"""

from __future__ import annotations

import json
import logging
import os
import shutil
import subprocess
import tempfile
from typing import Protocol

import anthropic
from pydantic import ValidationError

from .catalogue import DECISION_SCHEMA, Decision
from .prompt import SYSTEM_PROMPT

log = logging.getLogger(__name__)

API_MODEL = "claude-opus-5-5"
# On a safety-classifier refusal the API retries on Anthropic's recommended fallback model.
API_FALLBACK_BETA = "server-side-fallback-2026-07-01"
CLAUDE_CODE_MODEL = "opus"
CLAUDE_CODE_TIMEOUT_SECONDS = 120


class Backend(Protocol):
    name: str

    def ask(self, user: str) -> tuple[Decision, dict | None]: ...


class OfflineBackend:
    name = "offline"

    def ask(self, user: str) -> tuple[Decision, dict | None]:
        return Decision.wait("offline mode"), None


class ApiBackend:
    name = "api"

    def __init__(self, effort: str) -> None:
        self.effort = effort
        self.client = anthropic.Anthropic()

    def ask(self, user: str) -> tuple[Decision, dict | None]:
        try:
            response = self.client.beta.messages.create(
                model=API_MODEL,
                max_tokens=8000,
                betas=[API_FALLBACK_BETA],
                fallbacks="default",
                cache_control={"type": "ephemeral"},
                output_config={
                    "effort": self.effort,
                    "format": {"type": "json_schema", "schema": DECISION_SCHEMA},
                },
                system=SYSTEM_PROMPT,
                messages=[{"role": "user", "content": user}],
            )
        except anthropic.APIStatusError as e:
            log.error("Claude API error %s: %s", e.status_code, e.message)
            return Decision.wait(f"API error {e.status_code}"), None
        except anthropic.APIConnectionError as e:
            log.error("Could not reach the Claude API: %s", e)
            return Decision.wait("API unreachable"), None

        usage = response.usage.model_dump(exclude_none=True)
        if response.stop_reason != "end_turn":
            detail = response.stop_details.category if response.stop_details else None
            log.warning("No decision: stop_reason=%s detail=%s", response.stop_reason, detail)
            return Decision.wait(f"no decision ({response.stop_reason})"), usage
        text = next(block.text for block in response.content if block.type == "text")
        return Decision.model_validate_json(text), usage


class ClaudeCodeBackend:
    name = "claude-code"

    def __init__(self, effort: str) -> None:
        executable = shutil.which("claude")
        if executable is None:
            raise SystemExit("The claude CLI is not on PATH; install Claude Code or use --backend api.")
        self.command = [
            executable,
            "-p",
            # Keep the login but load no CLAUDE.md, hooks, plugins, MCP servers or memory.
            "--safe-mode",
            # No tools: the director can only answer.
            "--tools", "",
            "--disable-slash-commands",
            "--no-session-persistence",
            "--model", CLAUDE_CODE_MODEL,
            "--effort", effort,
            "--system-prompt", SYSTEM_PROMPT,
            "--output-format", "json",
            "--json-schema", json.dumps(DECISION_SCHEMA),
        ]
        # An API key in the environment would take precedence over the subscription login.
        self.env = {k: v for k, v in os.environ.items() if k not in ("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN")}
        # Run outside any project so no project settings or files are picked up.
        self.cwd = tempfile.mkdtemp(prefix="ai-director-")

    def ask(self, user: str) -> tuple[Decision, dict | None]:
        try:
            completed = subprocess.run(
                self.command,
                input=user,
                capture_output=True,
                text=True,
                encoding="utf-8",
                timeout=CLAUDE_CODE_TIMEOUT_SECONDS,
                cwd=self.cwd,
                env=self.env,
            )
        except subprocess.TimeoutExpired:
            log.error("claude -p timed out after %d s", CLAUDE_CODE_TIMEOUT_SECONDS)
            return Decision.wait("Claude Code timed out"), None
        return parse_claude_code_output(completed.returncode, completed.stdout, completed.stderr)


def parse_claude_code_output(returncode: int, stdout: str, stderr: str) -> tuple[Decision, dict | None]:
    """Reads the `--output-format json` result of a `claude -p` run."""
    try:
        result = json.loads(stdout)
    except json.JSONDecodeError:
        log.error("claude -p exited %d without JSON output: %s", returncode, (stderr or stdout).strip()[:500])
        return Decision.wait(f"Claude Code failed (exit {returncode})"), None

    usage = {key: result[key] for key in ("usage", "total_cost_usd", "duration_ms") if key in result}
    if result.get("is_error") or "structured_output" not in result:
        log.error("claude -p gave no decision: %s %s", result.get("subtype"), str(result.get("result"))[:500])
        return Decision.wait(f"no decision ({result.get('subtype', 'error')})"), usage
    try:
        return Decision.model_validate(result["structured_output"]), usage
    except ValidationError as e:
        log.error("claude -p decision does not match the schema: %s", e)
        return Decision.wait("malformed decision"), usage


def make_backend(name: str, effort: str) -> Backend:
    match name:
        case "claude-code":
            return ClaudeCodeBackend(effort)
        case "api":
            return ApiBackend(effort)
        case "offline":
            return OfflineBackend()
    raise ValueError(f"unknown backend {name!r}")
