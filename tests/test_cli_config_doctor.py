#!/usr/bin/env python3
"""Behavior checks for the no-socket `cmux config doctor` command."""

from __future__ import annotations

import glob
import json
import os
import subprocess
import tempfile
from pathlib import Path


def resolve_cmux_cli() -> str:
    explicit = os.environ.get("CMUX_CLI_BIN") or os.environ.get("CMUX_CLI")
    if explicit and os.path.exists(explicit) and os.access(explicit, os.X_OK):
        return explicit

    candidates = [
        path
        for path in glob.glob(os.path.expanduser("~/Library/Developer/Xcode/DerivedData/*/Build/Products/Debug/cmux"))
        if os.path.exists(path) and os.access(path, os.X_OK)
    ]
    if candidates:
        candidates.sort(key=os.path.getmtime, reverse=True)
        return candidates[0]

    raise RuntimeError("Unable to find cmux CLI binary. Set CMUX_CLI_BIN.")


def run_cli(cli_path: str, args: list[str], home: Path) -> subprocess.CompletedProcess[str]:
    env = dict(os.environ)
    env["HOME"] = str(home)
    env["CMUX_CLI_SENTRY_DISABLED"] = "1"
    env["CMUX_SOCKET_PATH"] = str(home / "missing.sock")
    env.pop("CMUX_SOCKET", None)
    env.pop("CMUX_SOCKET_PASSWORD", None)
    env.pop("CMUX_WORKSPACE_ID", None)
    env.pop("CMUX_SURFACE_ID", None)
    env.pop("CMUX_TAB_ID", None)
    return subprocess.run(
        [cli_path, *args],
        text=True,
        capture_output=True,
        env=env,
        timeout=5,
        check=False,
    )


def main() -> int:
    cli_path = resolve_cmux_cli()
    failures: list[str] = []

    with tempfile.TemporaryDirectory(prefix="cmux-config-doctor-") as temp:
        home = Path(temp)
        config_path = home / ".config" / "cmux" / "cmux.json"
        config_path.parent.mkdir(parents=True)
        config_path.write_text(
            """
            {
              // JSONC comments and trailing commas are valid in cmux.json.
              "schemaVersion": 1,
              "app": {
                "appearance": "system",
              },
            }
            """,
            encoding="utf-8",
        )

        ok_result = run_cli(cli_path, ["--json", "config", "doctor", "--path", str(config_path)], home)
        if ok_result.returncode != 0:
            failures.append(f"valid JSONC returned {ok_result.returncode}: {ok_result.stderr}")
        else:
            payload = json.loads(ok_result.stdout)
            finding = payload["findings"][0]
            if payload["ok"] is not True or finding["status"] != "ok":
                failures.append(f"valid JSONC was not ok: {ok_result.stdout}")
            if "app" not in finding["keys"] or "schemaVersion" not in finding["keys"]:
                failures.append(f"valid JSONC keys missing: {ok_result.stdout}")

        config_path.write_text("{\n", encoding="utf-8")
        bad_result = run_cli(cli_path, ["--json", "config", "doctor", "--path", str(config_path)], home)
        if bad_result.returncode == 0:
            failures.append("invalid JSON returned success")
        else:
            payload = json.loads(bad_result.stdout)
            finding = payload["findings"][0]
            if payload["ok"] is not False or finding["status"] != "error":
                failures.append(f"invalid JSON did not report an error: {bad_result.stdout}")
            if "cmux config doctor found 1 error(s)" not in bad_result.stderr:
                failures.append(f"invalid JSON stderr was unexpected: {bad_result.stderr}")

    if failures:
        for failure in failures:
            print(f"FAIL: {failure}")
        return 1

    print("PASS: cmux config doctor validates JSONC and reports syntax errors")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
