#!/usr/bin/env python3
"""Regression: relayed room prompts are not re-published (loop guard).

A message typed into one wired agent is relayed into the peer's terminal as a
"Shared room message from surface ..." prompt. When the peer processes it, its
own prompt-submit hook fires. If that re-published the prompt into the room it
would echo back and loop forever. The publish hook must skip prompts it can see
were relayed, while still publishing genuine user prompts.
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


class HookSocketServer:
    def __init__(self, workspace_id: str, surface_id: str) -> None:
        self.workspace_id = workspace_id
        self.surface_id = surface_id
        self.commands: list[str] = []
        self.ready = threading.Event()
        self.stop = threading.Event()
        self.error: Exception | None = None
        self.root = tempfile.TemporaryDirectory(prefix="cmux-room-relay-")
        self.socket_path = os.path.join(self.root.name, "cmux.sock")
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.server: socket.socket | None = None

    def __enter__(self) -> "HookSocketServer":
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
                    conn.sendall((self._response_for(line) + "\n").encode("utf-8"))

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

        return json.dumps({"id": request.get("id"), "ok": True, "result": result})


def run_claude_hook(cli_path, socket_path, subcommand, payload, env) -> None:
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


def has_room_post(commands: list[str]) -> bool:
    return any('"method":"agent.room.post"' in command for command in commands)


def main() -> int:
    try:
        cli_path = resolve_cmux_cli()
    except Exception as exc:
        print(f"FAIL: {exc}")
        return 1

    workspace_id = str(uuid.uuid4()).upper()
    surface_id = str(uuid.uuid4()).upper()
    peer_surface_id = str(uuid.uuid4()).upper()
    session_id = f"sess-{uuid.uuid4().hex}"

    with HookSocketServer(workspace_id=workspace_id, surface_id=surface_id) as server:
        env = os.environ.copy()
        env["CMUX_SOCKET_PATH"] = server.socket_path
        env["CMUX_WORKSPACE_ID"] = workspace_id
        env["CMUX_SURFACE_ID"] = surface_id
        env["CMUX_CLI_SENTRY_DISABLED"] = "1"
        env["CMUX_CLAUDE_HOOK_SENTRY_DISABLED"] = "1"

        run_claude_hook(
            cli_path,
            server.socket_path,
            "session-start",
            {"session_id": session_id, "source": "startup", "cwd": "/tmp"},
            env,
        )

        # Control: a genuine user prompt IS published to the room. This proves
        # the hook reaches the publish step, so a missing post in the relay case
        # is the loop guard working, not the hook bailing early.
        control_start = len(server.commands)
        run_claude_hook(
            cli_path,
            server.socket_path,
            "prompt-submit",
            {
                "session_id": session_id,
                "turn_id": "turn-1",
                "cwd": "/tmp",
                "prompt": "the british are coming",
            },
            env,
        )
        control_commands = server.commands[control_start:]
        if not has_room_post(control_commands):
            print("FAIL: genuine user prompt should be published to the room")
            print(f"control_commands={control_commands!r}")
            return 1

        # Relay: a prompt the app injected from a peer must NOT be re-published,
        # or it would echo back into the room and loop.
        relay_prompt = (
            f"Shared room message from surface {peer_surface_id}:\n"
            "the british are coming\n\n"
            "Please respond or continue from this shared-room update."
        )
        relay_start = len(server.commands)
        run_claude_hook(
            cli_path,
            server.socket_path,
            "prompt-submit",
            {
                "session_id": session_id,
                "turn_id": "turn-2",
                "cwd": "/tmp",
                "prompt": relay_prompt,
            },
            env,
        )
        relay_commands = server.commands[relay_start:]
        if has_room_post(relay_commands):
            print("FAIL: relayed room prompt must not be re-published (loop guard)")
            print(f"relay_commands={relay_commands!r}")
            return 1

    print("PASS: relayed room prompts are not re-published; genuine prompts are")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
