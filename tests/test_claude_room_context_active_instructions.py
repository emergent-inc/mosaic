#!/usr/bin/env python3
"""Regression: Claude room context teaches agents how to actively hand off."""

from __future__ import annotations

import json
import os
import shutil
import socket
import subprocess
import tempfile
import threading
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


class RoomContextSocketServer:
    def __init__(self, workspace_id: str, surface_id: str, peer_surface_id: str) -> None:
        self.workspace_id = workspace_id
        self.surface_id = surface_id
        self.peer_surface_id = peer_surface_id
        self.commands: list[str] = []
        self.ready = threading.Event()
        self.stop = threading.Event()
        self.error: Exception | None = None
        self.root = tempfile.TemporaryDirectory(prefix="cmux-room-context-")
        self.socket_path = os.path.join(self.root.name, "cmux.sock")
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.server: socket.socket | None = None

    def __enter__(self) -> "RoomContextSocketServer":
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
            while not self.stop.is_set():
                try:
                    chunk = conn.recv(4096)
                except socket.timeout:
                    continue
                if not chunk:
                    break
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
        if method == "workspace.current":
            result = {"workspace_id": self.workspace_id}
        elif method == "workspace.list":
            result = {"workspaces": [{"id": self.workspace_id, "ref": "workspace:1"}]}
        elif method == "window.list":
            result = {"windows": [{"id": str(uuid.uuid4()).upper()}]}
        elif method == "surface.list":
            result = {
                "surfaces": [
                    {"id": self.surface_id, "ref": "surface:1", "focused": True},
                    {"id": self.peer_surface_id, "ref": "surface:2", "focused": False},
                ]
            }
        elif method == "debug.terminals":
            result = {"terminals": []}
        elif method == "agent.room.digest":
            result = {
                "room_id": "room-1",
                "digest": "[1] message: Shared user message: build a website",
                "context_pack_text": "Queryable transcript excerpts:\n- [1] claude/assistant: Claude A found the auth regression.",
                "last_sequence": 1,
                "current_surface_id": self.surface_id,
                "reachable_surfaces": [
                    {
                        "member_id": "member-b",
                        "surface_id": self.peer_surface_id,
                        "display_name": "Claude B",
                    }
                ],
            }

        return json.dumps({"id": request.get("id"), "ok": True, "result": result})


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
    peer_surface_id = str(uuid.uuid4()).upper()

    with RoomContextSocketServer(workspace_id, surface_id, peer_surface_id) as server:
        env = os.environ.copy()
        env["CMUX_SOCKET_PATH"] = server.socket_path
        env["CMUX_WORKSPACE_ID"] = workspace_id
        env["CMUX_SURFACE_ID"] = surface_id
        env["CMUX_CLI_SENTRY_DISABLED"] = "1"
        env["CMUX_CLAUDE_HOOK_SENTRY_DISABLED"] = "1"

        proc = subprocess.run(
            [cli_path, "--socket", server.socket_path, "claude-hook", "room-context"],
            input=json.dumps({"session_id": "sess-room-context", "cwd": "/tmp"}),
            text=True,
            capture_output=True,
            env=env,
            timeout=8,
            check=False,
        )

    if proc.returncode != 0:
        print(f"stdout={proc.stdout!r}")
        print(f"stderr={proc.stderr!r}")
        return fail("claude-hook room-context failed")

    try:
        payload = json.loads(proc.stdout)
        additional = payload["hookSpecificOutput"]["additionalContext"]
    except Exception as exc:
        print(f"stdout={proc.stdout!r}")
        return fail(f"room-context did not emit hook JSON: {exc}")

    expected = f"cmux agent-room post --kind handoff --target-surfaces {peer_surface_id}"
    if "Reachable cmux room peers:" not in additional:
        return fail(f"missing reachable peer section: {additional!r}")
    if "Claude B" not in additional or peer_surface_id not in additional:
        return fail(f"missing peer label/surface id: {additional!r}")
    if "Claude A found the auth regression." not in additional:
        return fail(f"missing peer transcript context: {additional!r}")
    if expected not in additional:
        return fail(f"missing active handoff command {expected!r}: {additional!r}")
    if "built-in background-agent messaging" not in additional:
        return fail(f"missing guidance away from Claude built-in messaging: {additional!r}")

    print("PASS: Claude room context includes active handoff instructions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
