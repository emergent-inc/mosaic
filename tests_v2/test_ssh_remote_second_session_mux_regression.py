#!/usr/bin/env python3
"""Regression: opening a second `mosaic ssh` workspace to the same host must not mux-refuse."""

from __future__ import annotations

import glob
import json
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from mosaic import mosaic, mosaicError


SOCKET_PATH = os.environ.get("MOSAIC_SOCKET_PATH", "/tmp/mosaic-debug.sock")
SSH_HOST = os.environ.get("MOSAIC_SSH_TEST_HOST", "").strip()


def _must(cond: bool, msg: str) -> None:
    if not cond:
        raise mosaicError(msg)


def _find_cli_binary() -> str:
    env_cli = os.environ.get("MOSAICTERM_CLI")
    if env_cli and os.path.isfile(env_cli) and os.access(env_cli, os.X_OK):
        return env_cli

    fixed = os.path.expanduser("~/Library/Developer/Xcode/DerivedData/mosaic-tests-v2/Build/Products/Debug/mosaic")
    if os.path.isfile(fixed) and os.access(fixed, os.X_OK):
        return fixed

    candidates = glob.glob(os.path.expanduser("~/Library/Developer/Xcode/DerivedData/**/Build/Products/Debug/mosaic"), recursive=True)
    candidates += glob.glob("/tmp/mosaic-*/Build/Products/Debug/mosaic")
    candidates = [p for p in candidates if os.path.isfile(p) and os.access(p, os.X_OK)]
    if not candidates:
        raise mosaicError("Could not locate mosaic CLI binary; set MOSAICTERM_CLI")
    candidates.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return candidates[0]


def _run_cli_json(cli: str, args: list[str]) -> dict:
    env = dict(os.environ)
    env.pop("MOSAIC_WORKSPACE_ID", None)
    env.pop("MOSAIC_SURFACE_ID", None)
    env.pop("MOSAIC_TAB_ID", None)

    import subprocess

    proc = subprocess.run(
        [cli, "--socket", SOCKET_PATH, "--json", *args],
        capture_output=True,
        text=True,
        check=False,
        env=env,
    )
    if proc.returncode != 0:
        raise mosaicError(f"CLI failed ({' '.join(args)}): {(proc.stdout + proc.stderr).strip()}")
    try:
        return json.loads(proc.stdout or "{}")
    except Exception as exc:  # noqa: BLE001
        raise mosaicError(f"Invalid JSON output for {' '.join(args)}: {proc.stdout!r} ({exc})")


def _wait_remote_ready(client: mosaic, workspace_id: str, timeout: float = 20.0) -> None:
    deadline = time.time() + timeout
    last_status = {}
    while time.time() < deadline:
        last_status = client._call("workspace.remote.status", {"workspace_id": workspace_id}) or {}
        remote = last_status.get("remote") or {}
        daemon = remote.get("daemon") or {}
        if str(remote.get("state") or "") == "connected" and str(daemon.get("state") or "") == "ready":
            return
        time.sleep(0.25)
    raise mosaicError(f"Remote did not become ready for {workspace_id}: {last_status}")


def _wait_surface_id(client: mosaic, workspace_id: str, timeout: float = 10.0) -> str:
    deadline = time.time() + timeout
    while time.time() < deadline:
        surfaces = client.list_surfaces(workspace_id)
        if surfaces:
            return str(surfaces[0][1])
        time.sleep(0.1)
    raise mosaicError(f"No terminal surface appeared for workspace {workspace_id}")


def _workspace_id_from_payload(client: mosaic, payload: dict) -> str:
    workspace_id = str(payload.get("workspace_id") or "")
    if workspace_id:
        return workspace_id
    workspace_ref = str(payload.get("workspace_ref") or "")
    if workspace_ref.startswith("workspace:"):
        rows = (client._call("workspace.list", {}) or {}).get("workspaces") or []
        for row in rows:
            if str(row.get("ref") or "") == workspace_ref:
                return str(row.get("id") or "")
    return ""


def _wait_text_contains(client: mosaic, surface_id: str, needle: str, timeout: float = 8.0) -> str:
    deadline = time.time() + timeout
    last = ""
    while time.time() < deadline:
        last = client.read_terminal_text(surface_id)
        if needle in last:
            return last
        time.sleep(0.1)
    raise mosaicError(f"Timed out waiting for {needle!r} in surface {surface_id}: {last[-800:]!r}")


def main() -> int:
    if not SSH_HOST:
        print("SKIP: set MOSAIC_SSH_TEST_HOST to run second-session ssh mux regression")
        return 0

    cli = _find_cli_binary()
    workspace_ids: list[str] = []
    try:
        with mosaic(SOCKET_PATH) as client:
            first = _run_cli_json(cli, ["ssh", SSH_HOST])
            first_workspace_id = _workspace_id_from_payload(client, first)
            _must(bool(first_workspace_id), f"first mosaic ssh output missing workspace_id: {first}")
            workspace_ids.append(first_workspace_id)
            _wait_remote_ready(client, first_workspace_id)
            first_surface_id = _wait_surface_id(client, first_workspace_id)
            _wait_text_contains(client, first_surface_id, "mosaic in ~", timeout=12.0)

            second = _run_cli_json(cli, ["ssh", SSH_HOST])
            second_workspace_id = _workspace_id_from_payload(client, second)
            _must(bool(second_workspace_id), f"second mosaic ssh output missing workspace_id: {second}")
            _must(
                second_workspace_id != first_workspace_id,
                f"second mosaic ssh should create a distinct workspace: {first_workspace_id} vs {second_workspace_id}",
            )
            workspace_ids.append(second_workspace_id)
            _wait_remote_ready(client, second_workspace_id)

            second_surface_id = _wait_surface_id(client, second_workspace_id)
            text = _wait_text_contains(client, second_surface_id, "mosaic in ~", timeout=12.0)

            refusal_markers = [
                "mux_client_request_session: session request failed: Session open refused by peer",
                "ControlSocket ",
                "disabling multiplexing",
            ]
            hits = [marker for marker in refusal_markers if marker in text]
            _must(
                not hits,
                "second mosaic ssh session printed mux refusal text instead of starting cleanly: "
                f"markers={hits!r} tail={text[-1200:]!r}",
            )

            client.send_surface(second_surface_id, "printf '__SECOND_SESSION_OK__\\n'")
            text = _wait_text_contains(client, second_surface_id, "__SECOND_SESSION_OK__", timeout=6.0)
            _must(
                "command not found" not in text,
                f"second mosaic ssh session accepted corrupted input after startup: {text[-1200:]!r}",
            )
    finally:
        if workspace_ids:
            try:
                with mosaic(SOCKET_PATH) as client:
                    for workspace_id in workspace_ids:
                        try:
                            client._call("workspace.close", {"workspace_id": workspace_id})
                        except Exception:
                            pass
            except Exception:
                pass

    print("PASS: second mosaic ssh session opens cleanly without mux refusal")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
