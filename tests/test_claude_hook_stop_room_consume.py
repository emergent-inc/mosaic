#!/usr/bin/env python3
"""Regression: hivemind delivery is push-published, invisible, and cursor-gated.

The deterministic room pipeline:
- `prompt-submit` (UserPromptSubmit) PUSHES the user's prompt into the room
  ledger via `agent.room.post` (kind message), skipping relayed prompts so
  nothing echoes back into the room.
- `room-context` (UserPromptSubmit) is the single cursor-gated delivery
  channel: it drains `agent.room.consume` and injects the pending text
  invisibly via `hookSpecificOutput.additionalContext`.
- `session-start` (SessionStart) re-seeds a (re)started session with a full
  room recap via `agent.room.recap` + additionalContext, fixing restart
  amnesia (the app resets the member cursor when serving the recap).
- `stop` must NOT participate in delivery: a Stop-hook `decision:block` is
  rendered visibly and force-continues an idle agent (loop + spam), and a
  consume here would swallow the cursor before the peer's next prompt.
"""

from __future__ import annotations

import json
import os
import shutil
import socket
import subprocess
import tempfile
import threading
import time
import uuid


def resolve_cmux_cli() -> str:
    explicit = os.environ.get("CMUX_CLI_BIN") or os.environ.get("CMUX_CLI")
    if explicit:
        if os.path.exists(explicit) and os.access(explicit, os.X_OK):
            return explicit
        raise RuntimeError(f"Configured cmux CLI is not executable: {explicit}")

    in_path = shutil.which("cmux")
    if in_path:
        return in_path

    raise RuntimeError("Unable to find cmux CLI binary. Set CMUX_CLI_BIN.")


class RoomHookSocketServer:
    def __init__(self, workspace_id: str, surface_id: str) -> None:
        self.workspace_id = workspace_id
        self.surface_id = surface_id
        self.commands: list[str] = []
        # Toggled per-run to steer what the room verbs return.
        self.consume_text = ""
        self.recap_text = ""
        self.ready = threading.Event()
        self.stop = threading.Event()
        self.error: Exception | None = None
        self.root = tempfile.TemporaryDirectory(prefix="cmux-room-hook-")
        self.socket_path = os.path.join(self.root.name, "cmux.sock")
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.server: socket.socket | None = None

    def __enter__(self) -> "RoomHookSocketServer":
        self.thread.start()
        if not self.ready.wait(timeout=2.0):
            raise RuntimeError("socket server did not become ready")
        if self.error is not None:
            raise self.error
        return self

    def __exit__(self, _exc_type: object, _exc: object, _tb: object) -> None:
        self.stop.set()
        if self.server is not None:
            self.server.close()
        self.thread.join(timeout=2.0)
        self.root.cleanup()

    def _run(self) -> None:
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
                self.server = server
                server.bind(self.socket_path)
                server.listen(8)
                server.settimeout(0.1)
                self.ready.set()
                while not self.stop.is_set():
                    try:
                        conn, _ = server.accept()
                    except socket.timeout:
                        continue
                    except OSError:
                        return
                    threading.Thread(target=self._handle, args=(conn,), daemon=True).start()
        except Exception as exc:
            self.error = exc
            self.ready.set()

    def _handle(self, conn: socket.socket) -> None:
        with conn:
            conn.settimeout(0.1)
            buffer = b""
            idle_deadline = time.time() + 6.0
            while not self.stop.is_set() and time.time() < idle_deadline:
                try:
                    chunk = conn.recv(4096)
                except socket.timeout:
                    continue
                if not chunk:
                    break
                idle_deadline = time.time() + 2.0
                buffer += chunk
                while b"\n" in buffer:
                    raw_line, buffer = buffer.split(b"\n", 1)
                    if not raw_line:
                        continue
                    line = raw_line.decode("utf-8", errors="replace")
                    self.commands.append(line)
                    try:
                        conn.sendall((self._response_for(line) + "\n").encode("utf-8"))
                    except BrokenPipeError:
                        return

    def _response_for(self, line: str) -> str:
        if not line.startswith("{"):
            return "OK"
        try:
            request = json.loads(line)
        except json.JSONDecodeError:
            return "OK"

        method = request.get("method")
        result: dict[str, object] = {}
        if method == "surface.list":
            result = {
                "surfaces": [
                    {"index": 0, "id": self.surface_id, "ref": "surface:1", "focused": True}
                ]
            }
        elif method == "workspace.current":
            result = {"workspace_id": self.workspace_id}
        elif method == "workspace.list":
            result = {"workspaces": [{"index": 0, "id": self.workspace_id, "ref": "workspace:1"}]}
        elif method == "window.list":
            result = {"windows": [{"id": str(uuid.uuid4()).upper()}]}
        elif method == "debug.terminals":
            result = {"terminals": []}
        elif method == "agent.room.digest":
            result = {"digest": "", "context_pack_text": "", "reachable_surfaces": []}
        elif method == "agent.room.consume":
            result = {"text": self.consume_text}
        elif method == "agent.room.recap":
            result = {"text": self.recap_text}
        elif method == "agent.room.post":
            result = {"posted": True}

        return json.dumps({"id": request.get("id"), "ok": True, "result": result})


def run_claude_hook(cli_path, socket_path, subcommand, payload, env):
    proc = subprocess.run(
        [cli_path, "--socket", socket_path, "claude-hook", subcommand],
        input=json.dumps(payload),
        text=True,
        capture_output=True,
        env=env,
        timeout=8,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            f"cmux claude-hook {subcommand} failed:\n"
            f"exit={proc.returncode}\nstdout={proc.stdout}\nstderr={proc.stderr}"
        )
    return proc.stdout


def commands_with(commands: list[str], method: str) -> list[str]:
    return [command for command in commands if f'"method":"{method}"' in command]


def fail(message: str) -> int:
    print(f"FAIL: {message}")
    return 1


def main() -> int:
    try:
        cli_path = resolve_cmux_cli()
    except Exception as exc:
        return fail(str(exc))

    workspace_id = str(uuid.uuid4()).upper()
    surface_id = str(uuid.uuid4()).upper()
    session_id = f"sess-{uuid.uuid4().hex}"

    with RoomHookSocketServer(workspace_id=workspace_id, surface_id=surface_id) as server:
        env = os.environ.copy()
        env["CMUX_SOCKET_PATH"] = server.socket_path
        env["CMUX_WORKSPACE_ID"] = workspace_id
        env["CMUX_SURFACE_ID"] = surface_id
        env["CMUX_CLI_SENTRY_DISABLED"] = "1"
        env["CMUX_CLAUDE_HOOK_SENTRY_DISABLED"] = "1"
        # Isolate the hook session store so parallel test runs never collide.
        state_dir = tempfile.mkdtemp(prefix="cmux-room-hook-state-")
        env["CMUX_AGENT_HOOK_STATE_DIR"] = state_dir

        # Case 1: session-start with no room content registers and prints OK.
        stdout = run_claude_hook(
            cli_path,
            server.socket_path,
            "session-start",
            {"session_id": session_id, "source": "startup", "cwd": "/tmp"},
            env,
        )
        if "OK" not in stdout:
            return fail(f"session-start with empty recap should print OK: stdout={stdout!r}")

        # Case 2: session-start with room history injects a recap invisibly via
        # SessionStart additionalContext (restart-amnesia fix).
        server.recap_text = "[1] message: Shared user message: the british are coming"
        recap_start = len(server.commands)
        stdout = run_claude_hook(
            cli_path,
            server.socket_path,
            "session-start",
            {"session_id": session_id, "source": "resume", "cwd": "/tmp"},
            env,
        )
        if not commands_with(server.commands[recap_start:], "agent.room.recap"):
            return fail("session-start did not query agent.room.recap")
        try:
            recap = json.loads(stdout.strip())
        except Exception:
            return fail(f"session-start with recap should emit JSON: stdout={stdout!r}")
        recap_context = (
            recap.get("hookSpecificOutput", {}).get("additionalContext", "")
            if isinstance(recap, dict)
            else ""
        )
        if "the british are coming" not in recap_context:
            return fail(f"session-start should inject recap via additionalContext: {recap!r}")
        if recap.get("hookSpecificOutput", {}).get("hookEventName") != "SessionStart":
            return fail(f"recap must be SessionStart hook output: {recap!r}")
        server.recap_text = ""

        # Case 3: prompt-submit PUSHES the user prompt into the room ledger.
        post_start = len(server.commands)
        stdout = run_claude_hook(
            cli_path,
            server.socket_path,
            "prompt-submit",
            {"session_id": session_id, "cwd": "/tmp", "prompt": "the british are coming"},
            env,
        )
        posts = commands_with(server.commands[post_start:], "agent.room.post")
        if not posts or "the british are coming" not in posts[0]:
            return fail(f"prompt-submit must post the user prompt to the room: {posts!r}")

        # Case 4: a relayed prompt must NOT be re-published (echo loop guard).
        relay_start = len(server.commands)
        run_claude_hook(
            cli_path,
            server.socket_path,
            "prompt-submit",
            {
                "session_id": session_id,
                "cwd": "/tmp",
                "prompt": "Shared room message from surface peer:\nthe british are coming",
            },
            env,
        )
        if commands_with(server.commands[relay_start:], "agent.room.post"):
            return fail("prompt-submit must not re-publish a relayed room prompt")

        # Case 5: room-context is the delivery channel — pending shared text is
        # injected silently via additionalContext, never as a block decision.
        server.consume_text = "Shared room message from surface peer:\nthe british are coming"
        ctx_start = len(server.commands)
        stdout = run_claude_hook(
            cli_path,
            server.socket_path,
            "room-context",
            {"session_id": session_id, "cwd": "/tmp", "prompt": "hi"},
            env,
        )
        if not commands_with(server.commands[ctx_start:], "agent.room.consume"):
            return fail("room-context hook did not query agent.room.consume")
        try:
            ctx = json.loads(stdout.strip())
        except Exception:
            return fail(f"room-context with pending text should emit JSON: stdout={stdout!r}")
        additional = (
            ctx.get("hookSpecificOutput", {}).get("additionalContext", "")
            if isinstance(ctx, dict)
            else ""
        )
        if "the british are coming" not in additional:
            return fail(f"room-context should inject pending text via additionalContext: {ctx!r}")
        if ctx.get("decision") == "block":
            return fail(f"room-context must never emit a visible block decision: {ctx!r}")

        # Case 6: the Stop hook must NOT deliver room content. Even with pending
        # text available, it prints OK, never blocks, and never consumes (which
        # would swallow the cursor before the peer's next prompt).
        server.consume_text = "Shared room message from surface peer:\nmore work"
        stop_start = len(server.commands)
        stdout = run_claude_hook(
            cli_path,
            server.socket_path,
            "stop",
            {"session_id": session_id, "cwd": "/tmp"},
            env,
        )
        if '"decision"' in stdout or "block" in stdout:
            return fail(f"stop hook must not block for room content: stdout={stdout!r}")
        if "OK" not in stdout:
            return fail(f"stop hook should print OK: stdout={stdout!r}")
        if commands_with(server.commands[stop_start:], "agent.room.consume"):
            return fail("stop hook must not call agent.room.consume (delivery moved to room-context)")

        # Case 7: room-context with nothing pending emits no injection.
        server.consume_text = ""
        stdout = run_claude_hook(
            cli_path,
            server.socket_path,
            "room-context",
            {"session_id": session_id, "cwd": "/tmp", "prompt": "hi again"},
            env,
        )
        if "the british are coming" in stdout or "more work" in stdout:
            return fail(f"room-context with no pending text must not re-inject: stdout={stdout!r}")

    print("PASS: push publish, invisible delivery, session-start recap, stop stays out")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
