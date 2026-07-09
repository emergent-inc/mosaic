#!/usr/bin/env python3
"""Regression: assistant replies must relay to wired peers, and the Stop hook
must trigger the app-side wake flush.

Two failure modes this locks down (both hit in the field — a peer asked for a
schema that a wired agent had just produced, got a 500-char truncated ledger
entry, and the targeted question never woke the idle author):

1. `room-publish` (Stop) posted the turn as a ledger-only `summary` event
   truncated to 500 characters. `summary` events are never injected into
   peers by `agent.room.consume`, so assistant replies silently never reached
   the other wired agents. The reply must be posted as a broadcastable
   `message` event carrying the full reply text (bounded well above the old
   500-char cap).

2. Delivery was purely pull-based: a targeted question/handoff/blocker sat in
   the ledger until the *user* manually prompted the target pane. The Stop
   hook must call `agent.room.wake_flush` so the app can type pending
   targeted wake events into the now-idle pane.

Second field round (both hit again after the 500-char fix shipped):

3. The hook-payload parser compacts every string field to ~240 chars for
   feed/notification use, and the room publishers read the *compacted* payload.
   A prompt or `last_assistant_message` longer than 240 chars relayed truncated
   even though the publish cap was 4,000 — and, because the compacted value was
   non-nil, the full-text transcript fallback never ran. The publishers must
   read the raw payload.

4. `agent-room post` without `--from-surface` let the app fall back to the
   *focused* panel as the sender. An agent answering a question got its handoff
   attributed to the pane the user was watching — the target itself — so the
   self-addressed event was never delivered. The CLI must default the sender
   from `MOSAIC_SURFACE_ID`.
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


def resolve_mosaic_cli() -> str:
    explicit = os.environ.get("MOSAIC_CLI_BIN") or os.environ.get("MOSAIC_CLI")
    if explicit:
        if os.path.exists(explicit) and os.access(explicit, os.X_OK):
            return explicit
        raise RuntimeError(f"Configured mosaic CLI is not executable: {explicit}")

    in_path = shutil.which("mosaic")
    if in_path:
        return in_path

    raise RuntimeError("Unable to find mosaic CLI binary. Set MOSAIC_CLI_BIN.")


class RoomHookSocketServer:
    def __init__(self, workspace_id: str, surface_id: str) -> None:
        self.workspace_id = workspace_id
        self.surface_id = surface_id
        self.commands: list[str] = []
        self.ready = threading.Event()
        self.stop = threading.Event()
        self.error: Exception | None = None
        self.root = tempfile.TemporaryDirectory(prefix="mosaic-room-wake-")
        self.socket_path = os.path.join(self.root.name, "mosaic.sock")
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
            result = {"text": ""}
        elif method == "agent.room.recap":
            result = {"text": ""}
        elif method == "agent.room.post":
            result = {"posted": True}
        elif method == "agent.room.wake_flush":
            result = {"woken": False}

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
            f"mosaic claude-hook {subcommand} failed:\n"
            f"exit={proc.returncode}\nstdout={proc.stdout}\nstderr={proc.stderr}"
        )
    return proc.stdout


def commands_with(commands: list[str], method: str) -> list[str]:
    return [command for command in commands if f'"method":"{method}"' in command]


def fail(message: str) -> int:
    print(f"FAIL: {message}")
    return 1


def write_transcript(path: str, user_text: str, assistant_text: str) -> None:
    lines = [
        {
            "type": "user",
            "uuid": str(uuid.uuid4()),
            "message": {"role": "user", "content": user_text},
        },
        {
            "type": "assistant",
            "uuid": str(uuid.uuid4()),
            "message": {
                "role": "assistant",
                "content": [{"type": "text", "text": assistant_text}],
            },
        },
    ]
    with open(path, "w", encoding="utf-8") as handle:
        for line in lines:
            handle.write(json.dumps(line) + "\n")


def main() -> int:
    try:
        cli_path = resolve_mosaic_cli()
    except Exception as exc:
        return fail(str(exc))

    workspace_id = str(uuid.uuid4()).upper()
    surface_id = str(uuid.uuid4()).upper()
    session_id = f"sess-{uuid.uuid4().hex}"

    with RoomHookSocketServer(workspace_id=workspace_id, surface_id=surface_id) as server:
        env = os.environ.copy()
        env["MOSAIC_SOCKET_PATH"] = server.socket_path
        env["MOSAIC_WORKSPACE_ID"] = workspace_id
        env["MOSAIC_SURFACE_ID"] = surface_id
        env["MOSAIC_CLI_SENTRY_DISABLED"] = "1"
        env["MOSAIC_CLAUDE_HOOK_SENTRY_DISABLED"] = "1"
        state_dir = tempfile.mkdtemp(prefix="mosaic-room-wake-state-")
        env["MOSAIC_AGENT_HOOK_STATE_DIR"] = state_dir

        # A multi-line assistant reply that a peer genuinely needs verbatim (a
        # schema). The end marker sits far past the old 500-char publish cap,
        # so its presence in the posted event proves the cap was lifted.
        schema_lines = [f"    column_{index:03d} BIGINT NOT NULL," for index in range(40)]
        assistant_reply = (
            "CREATE TABLE task_comments (\n"
            + "\n".join(schema_lines)
            + "\n    created_at TIMESTAMPTZ NOT NULL DEFAULT now()\n);"
            + "\n-- END_OF_SCHEMA_MARKER"
        )
        if len(assistant_reply) <= 900:
            return fail("test bug: assistant reply must exceed the old 500-char cap by a margin")

        transcript_path = os.path.join(state_dir, "transcript.jsonl")
        write_transcript(
            transcript_path,
            user_text="Design the database schema for a task-comment feature.",
            assistant_text=assistant_reply,
        )

        # Register the session so room-publish resolves the pane mapping the
        # same way a real Stop hook run does.
        run_claude_hook(
            cli_path,
            server.socket_path,
            "session-start",
            {
                "session_id": session_id,
                "source": "startup",
                "cwd": "/tmp",
                "transcript_path": transcript_path,
            },
            env,
        )

        publish_start = len(server.commands)
        run_claude_hook(
            cli_path,
            server.socket_path,
            "room-publish",
            {
                "session_id": session_id,
                "cwd": "/tmp",
                "transcript_path": transcript_path,
                # Real Stop payloads carry the reply inline. The parser compacts
                # this field to ~240 chars for feed use; the room publisher must
                # read the raw value (or it relays a truncated reply AND skips
                # the full-text transcript fallback because the compacted value
                # is non-nil).
                "last_assistant_message": assistant_reply,
            },
            env,
        )

        posts = commands_with(server.commands[publish_start:], "agent.room.post")
        if not posts:
            return fail("room-publish did not post the turn to the room")
        reply_posts = [post for post in posts if "Shared Claude reply" in post]
        if not reply_posts:
            return fail(f"room-publish must post the assistant reply: {posts!r}")
        reply_post = reply_posts[0]

        # 1a. The reply must be a broadcastable `message` event. A `summary`
        # event is ledger-only: agent.room.consume never injects it into
        # peers, so wired agents would never see each other's answers.
        try:
            reply_request = json.loads(reply_post)
        except json.JSONDecodeError:
            return fail(f"agent.room.post request is not JSON: {reply_post!r}")
        posted_kind = (reply_request.get("params") or {}).get("kind")
        if posted_kind != "message":
            return fail(
                "assistant reply must be posted as a broadcastable 'message' event, "
                f"got kind={posted_kind!r}"
            )

        # 1b. The full reply must survive: the end marker sits past the old
        # 500-char truncation point (and far past the parser's 240-char
        # payload compaction).
        posted_text = (reply_request.get("params") or {}).get("text") or ""
        if "END_OF_SCHEMA_MARKER" not in posted_text:
            return fail(
                "assistant reply was truncated before the end marker "
                f"(len={len(posted_text)}): {posted_text[-120:]!r}"
            )

        # 1c. Multi-line structure must survive too: the compacted payload
        # path normalized the reply to a single line, which mangles schemas
        # and code blocks for the receiving peer.
        if "\n-- END_OF_SCHEMA_MARKER" not in posted_text:
            return fail(
                "assistant reply lost its multi-line structure "
                f"(tail={posted_text[-120:]!r})"
            )

        # 2. The Stop hook must ask the app to flush pending targeted wake
        # events into this now-idle pane.
        flushes = commands_with(server.commands[publish_start:], "agent.room.wake_flush")
        if not flushes:
            return fail("room-publish must call agent.room.wake_flush for the settled pane")
        if surface_id not in flushes[0]:
            return fail(f"wake_flush must carry the pane's surface id: {flushes[0]!r}")

        # 3. A long user prompt must relay full-length. The parser compacts the
        # payload's `prompt` to ~240 chars for feed use; the relay publisher
        # must read the raw prompt or the seeded context peers were wired to
        # share arrives truncated.
        seed_lines = [f"- requirement {index:03d}: keep this line" for index in range(20)]
        seeded_prompt = (
            "Here is the context you need to share with your peer:\n"
            + "\n".join(seed_lines)
            + "\nEND_OF_PROMPT_MARKER"
        )
        if len(seeded_prompt) <= 500:
            return fail("test bug: seeded prompt must exceed the 240-char compaction by a margin")

        prompt_start = len(server.commands)
        run_claude_hook(
            cli_path,
            server.socket_path,
            "prompt-submit",
            {
                "session_id": session_id,
                "cwd": "/tmp",
                "transcript_path": transcript_path,
                "prompt": seeded_prompt,
            },
            env,
        )
        prompt_posts = [
            post
            for post in commands_with(server.commands[prompt_start:], "agent.room.post")
            if "Shared user message" in post
        ]
        if not prompt_posts:
            return fail("prompt-submit did not relay the user prompt to the room")
        try:
            prompt_request = json.loads(prompt_posts[0])
        except json.JSONDecodeError:
            return fail(f"agent.room.post request is not JSON: {prompt_posts[0]!r}")
        prompt_text = (prompt_request.get("params") or {}).get("text") or ""
        if "END_OF_PROMPT_MARKER" not in prompt_text:
            return fail(
                "user prompt was truncated before the end marker "
                f"(len={len(prompt_text)}): {prompt_text[-120:]!r}"
            )

        # 4. `agent-room post` without --from-surface must attribute the post
        # to the calling pane (MOSAIC_SURFACE_ID), not leave the sender for the
        # app to resolve from the focused panel. A focused-panel fallback can
        # attribute the post to its own target, and a self-addressed event is
        # never delivered.
        target_surface = str(uuid.uuid4()).upper()
        post_start = len(server.commands)
        proc = subprocess.run(
            [
                cli_path,
                "--socket",
                server.socket_path,
                "agent-room",
                "post",
                "--kind",
                "handoff",
                "--target-surfaces",
                target_surface,
                "--",
                "Full schema: CREATE TABLE task_comments (id BIGSERIAL PRIMARY KEY);",
            ],
            text=True,
            capture_output=True,
            env=env,
            timeout=8,
            check=False,
        )
        if proc.returncode != 0:
            return fail(
                f"agent-room post failed: exit={proc.returncode} "
                f"stdout={proc.stdout!r} stderr={proc.stderr!r}"
            )
        cli_posts = commands_with(server.commands[post_start:], "agent.room.post")
        if not cli_posts:
            return fail("agent-room post did not reach the socket")
        try:
            cli_post_request = json.loads(cli_posts[0])
        except json.JSONDecodeError:
            return fail(f"agent.room.post request is not JSON: {cli_posts[0]!r}")
        posted_from = (cli_post_request.get("params") or {}).get("from_surface_id")
        if posted_from != surface_id:
            return fail(
                "agent-room post must default from_surface_id to MOSAIC_SURFACE_ID "
                f"(expected {surface_id}, got {posted_from!r})"
            )

    print(
        "PASS: full-length reply and prompt relay, stop triggers wake flush, "
        "and agent-room post is attributed to the calling pane"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
