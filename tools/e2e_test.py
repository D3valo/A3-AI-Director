"""End-to-end test of the extension and companion, without Arma.

Loads the built ai_director_x64.dll through the same C entry points Arma uses (RVExtensionArgs,
RVExtensionRegisterCallback), starts the companion on a free port with a throwaway campaign folder, and checks
that a state sent the way the SQF sends it comes back as a decision through the callback, and that a stopped
companion comes back as an error.

    python tools/e2e_test.py [--backend offline|claude-code|api]

Uses the companion's venv; run it from anywhere. The default offline backend checks the plumbing only and costs
nothing; claude-code asks Claude for one real decision.
"""

import argparse
import ctypes
import json
import queue
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DLL = ROOT / "ai_director_x64.dll"
COMPANION = ROOT / "companion"
PYTHON = COMPANION / ".venv" / "Scripts" / "python.exe"
SAMPLE_STATE = COMPANION / "samples" / "state.json"

# int callback(const char *name, const char *function, const char *data), as Arma provides it.
CALLBACK = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p)


class Extension:
    """Calls the extension the way Arma's callExtension ["function", [args]] does."""

    def __init__(self, path: Path) -> None:
        self.dll = ctypes.CDLL(str(path))
        self.dll.RVExtensionArgs.restype = ctypes.c_int
        self.dll.RVExtensionArgs.argtypes = [
            ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p, ctypes.POINTER(ctypes.c_char_p), ctypes.c_int,
        ]
        self.callbacks: queue.Queue[tuple[str, str, str]] = queue.Queue()

        def on_callback(name: bytes, function: bytes, data: bytes) -> int:
            self.callbacks.put((name.decode(), function.decode(), (data or b"").decode()))
            return 0

        self._callback = CALLBACK(on_callback)  # keep a reference so it isn't garbage collected
        self.dll.RVExtensionRegisterCallback(self._callback)

    def call(self, function: str, *args: str) -> tuple[str, int]:
        # Arma passes string arguments in SQF string syntax: quoted, with inner quotes doubled.
        encoded = [('"' + a.replace('"', '""') + '"').encode() for a in args]
        argv = (ctypes.c_char_p * len(encoded))(*encoded)
        output = ctypes.create_string_buffer(20480)
        code = self.dll.RVExtensionArgs(output, len(output), function.encode(), argv, len(encoded))
        return output.value.decode(), code

    def next_callback(self, timeout: float) -> tuple[str, str, str]:
        return self.callbacks.get(timeout=timeout)


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def wait_for_health(url: str, seconds: float) -> None:
    deadline = time.monotonic() + seconds
    while True:
        try:
            with urllib.request.urlopen(f"{url}/health", timeout=1) as response:
                if response.status == 200:
                    return
        except OSError:
            if time.monotonic() > deadline:
                raise
            time.sleep(0.2)


def expect(condition: bool, message: str) -> None:
    print(("PASS " if condition else "FAIL ") + message)
    if not condition:
        raise SystemExit(1)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--backend", choices=["offline", "claude-code", "api"], default="offline")
    args = parser.parse_args()
    if not DLL.exists():
        raise SystemExit(f"{DLL} not found; run tools/build.ps1 first")

    ext = Extension(DLL)
    version, code = ext.call("version")
    expect(code == 0 and version != "", f"version {version!r}")

    port = free_port()
    url = f"http://127.0.0.1:{port}"
    expect(ext.call("set_url", url) == (url, 0), f"set_url {url}")
    expect(ext.call("set_url", "http://example.com")[1] == 9, "set_url refuses a remote host")

    with tempfile.TemporaryDirectory() as campaigns:
        companion = subprocess.Popen(
            [str(PYTHON), "-m", "director", "--backend", args.backend, "--campaigns-dir", campaigns,
             "--campaign", "e2e", "serve", "--port", str(port), "--no-report"],
            cwd=COMPANION, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        try:
            wait_for_health(url, 15)
            state = SAMPLE_STATE.read_text(encoding="utf-8")
            expect(ext.call("send_state", state) == ("sent", 0), "send_state sent")
            name, function, data = ext.next_callback(timeout=180)
            decision = json.loads(data)
            expect(
                (name, function) == ("ai_director", "decision") and "action" in decision,
                f"decision callback: {decision.get('action')} - {decision.get('reason')}",
            )
            logs = list(Path(campaigns, "e2e", "logs").glob("decisions-*.jsonl"))
            expect(len(logs) == 1, "decision logged in the campaign")
        finally:
            companion.terminate()
            companion.wait(timeout=10)

    expect(ext.call("send_state", "{}") == ("sent", 0), "send_state with the companion stopped")
    name, function, data = ext.next_callback(timeout=30)
    expect(function == "error", f"error callback: {data}")
    expect(ext.call("send_state", "{not json")[1] == 9, "send_state refuses invalid JSON")
    print("All end-to-end checks passed.")


if __name__ == "__main__":
    sys.exit(main())
