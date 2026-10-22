"""Ways of asking Claude for a structured answer. Each backend takes the system prompt as a list of blocks
that stay the same for a whole session (so they can be cached), a user message and a JSON schema, and returns
the answer as a dict (or None with an error) plus usage details for the log.

- ClaudeCodeBackend runs the local `claude` CLI in print mode, on the Claude subscription it is logged
  in with. For personal use only: never use it to serve other people's requests.
- ApiBackend calls the Claude API with an API key (ANTHROPIC_API_KEY or an `ant auth login` profile).
- OfflineBackend never answers, for testing the plumbing.
"""

from __future__ import annotations

import json
import logging
import os
import shutil
import subprocess
import tempfile
from dataclasses import dataclass
from typing import Protocol

import anthropic

log = logging.getLogger(__name__)

API_MODEL = "claude-opus-5-5"
# On a safety-classifier refusal the API retries on Anthropic's recommended fallback model.
API_FALLBACK_BETA = "server-side-fallback-2026-07-01"
CLAUDE_CODE_MODEL = "opus"
# A decision every 90 s and pauses of up to 5 min (--max-skip) sit at the 5-minute TTL's edge; the 1-hour TTL
# keeps the system prompt cached for the whole session, for a slightly dearer first write.
CACHE_CONTROL = {"type": "ephemeral", "ttl": "1h"}


@dataclass
class Answer:
    data: dict | None
    usage: dict | None = None
    error: str | None = None


class Backend(Protocol):
    name: str

    def structured(
        self, system: list[str], user: str, schema: dict, effort: str, timeout: float, cache: bool = True
    ) -> Answer: ...


class OfflineBackend:
    name = "offline"

    def structured(
        self, system: list[str], user: str, schema: dict, effort: str, timeout: float, cache: bool = True
    ) -> Answer:
        return Answer(None, error="offline mode")


class ApiBackend:
    name = "api"

    def __init__(self, client: anthropic.Anthropic | None = None) -> None:
        self.client = client or anthropic.Anthropic()

    def structured(
        self, system: list[str], user: str, schema: dict, effort: str, timeout: float, cache: bool = True
    ) -> Answer:
        try:
            response = self.client.with_options(timeout=timeout).beta.messages.create(
                model=API_MODEL,
                max_tokens=16000,
                betas=[API_FALLBACK_BETA],
                fallbacks="default",
                output_config={"effort": effort, "format": {"type": "json_schema", "schema": schema}},
                # The cache breakpoint goes on the last system block: everything before the user message.
                system=[
                    {"type": "text", "text": block}
                    | ({"cache_control": CACHE_CONTROL} if cache and i == len(system) - 1 else {})
                    for i, block in enumerate(system)
                ],
                messages=[{"role": "user", "content": user}],
            )
        except anthropic.APIStatusError as e:
            log.error("Claude API error %s: %s", e.status_code, e.message)
            return Answer(None, error=f"API error {e.status_code}")
        except anthropic.APIConnectionError as e:
            log.error("Could not reach the Claude API: %s", e)
            return Answer(None, error="API unreachable")

        usage = response.usage.model_dump(exclude_none=True)
        log.debug("Cache: %s tokens read, %s written", usage.get("cache_read_input_tokens", 0),
                  usage.get("cache_creation_input_tokens", 0))
        if response.stop_reason != "end_turn":
            detail = response.stop_details.category if response.stop_details else None
            log.warning("No answer: stop_reason=%s detail=%s", response.stop_reason, detail)
            return Answer(None, usage, f"no answer ({response.stop_reason})")
        text = next(block.text for block in response.content if block.type == "text")
        return Answer(json.loads(text), usage)


class ClaudeCodeBackend:
    name = "claude-code"

    def __init__(self) -> None:
        executable = shutil.which("claude")
        if executable is None:
            raise SystemExit("The claude CLI is not on PATH; install Claude Code or use --backend api.")
        self.executable = executable
        # An API key in the environment would take precedence over the subscription login.
        self.env = {k: v for k, v in os.environ.items() if k not in ("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN")}
        # Run outside any project so no project settings or files are picked up.
        self.cwd = tempfile.mkdtemp(prefix="ai-director-")

    def structured(
        self, system: list[str], user: str, schema: dict, effort: str, timeout: float, cache: bool = True
    ) -> Answer:
        command = [
            self.executable,
            "-p",
            # Keep the login but load no CLAUDE.md, hooks, plugins, MCP servers or memory.
            "--safe-mode",
            # No tools: Claude can only answer.
            "--tools", "",
            "--disable-slash-commands",
            "--no-session-persistence",
            "--model", CLAUDE_CODE_MODEL,
            "--effort", effort,
            # Claude Code caches its own prompt; the blocks are one prompt here.
            "--system-prompt", "\n\n".join(system),
            "--output-format", "json",
            "--json-schema", json.dumps(schema),
        ]
        try:
            completed = subprocess.run(
                command, input=user, capture_output=True, text=True, encoding="utf-8",
                timeout=timeout, cwd=self.cwd, env=self.env,
            )
        except subprocess.TimeoutExpired:
            log.error("claude -p timed out after %.0f s", timeout)
            return Answer(None, error="Claude Code timed out")
        return parse_claude_code_output(completed.returncode, completed.stdout, completed.stderr)


def parse_claude_code_output(returncode: int, stdout: str, stderr: str) -> Answer:
    """Reads the `--output-format json` result of a `claude -p` run."""
    try:
        result = json.loads(stdout)
    except json.JSONDecodeError:
        log.error("claude -p exited %d without JSON output: %s", returncode, (stderr or stdout).strip()[:500])
        return Answer(None, error=f"Claude Code failed (exit {returncode})")

    usage = {key: result[key] for key in ("usage", "total_cost_usd", "duration_ms") if key in result}
    if result.get("is_error") or not isinstance(result.get("structured_output"), dict):
        log.error("claude -p gave no answer: %s %s", result.get("subtype"), str(result.get("result"))[:500])
        return Answer(None, usage, f"no answer ({result.get('subtype', 'error')})")
    return Answer(result["structured_output"], usage)


def make_backend(name: str) -> Backend:
    match name:
        case "claude-code":
            return ClaudeCodeBackend()
        case "api":
            return ApiBackend()
        case "offline":
            return OfflineBackend()
    raise ValueError(f"unknown backend {name!r}")
