---
name: mosaic-diagnostics
description: "Run end-user mosaic diagnostics. Use when mosaic hooks, notifications, session restore, settings, browser automation, socket access, CLI control, or agent resume behavior is not working, or when the user asks for a mosaic health check, doctor report, or support-safe debug summary."
---

# mosaic Diagnostics

Use this skill to collect and interpret support-safe mosaic diagnostics for end users. Default to read-only checks. Do not dump hook config files, session stores, prompt logs, tokens, or environment secrets.

## Quick Report

Run the bundled read-only diagnostic script first:

```bash
# From a mosaic checkout
skills/mosaic-diagnostics/scripts/mosaic-diagnostics

# From an installed skill
~/.agents/skills/mosaic-diagnostics/scripts/mosaic-diagnostics

# From a Codex-only skills.sh install
~/.codex/skills/mosaic-diagnostics/scripts/mosaic-diagnostics
```

Use `--include-context` only when workspace names, cwd paths, and current mosaic identifiers are relevant to the user-reported issue:

```bash
skills/mosaic-diagnostics/scripts/mosaic-diagnostics --include-context
```

## What to Check

1. CLI and socket health:

   ```bash
   command -v mosaic
   mosaic ping
   mosaic capabilities --json
   ```

   If socket commands fail, check whether the agent is running inside a mosaic terminal and whether socket automation is enabled.

2. Settings health:

   ```bash
   ~/.agents/skills/mosaic-settings/scripts/mosaic-settings validate
   ~/.agents/skills/mosaic-settings/scripts/mosaic-settings get terminal.autoResumeAgentSessions
   ```

   If the user installed with `skills.sh`, use `~/.codex/skills/mosaic-settings/scripts/mosaic-settings` instead.
   If `terminal.autoResumeAgentSessions` is false, mosaic restores panes but will not automatically resume saved agent sessions.

3. Hook installation:

   ```bash
   mosaic hooks setup --agent codex
   mosaic hooks setup --agent opencode
   mosaic hooks setup
   ```

   Only run install or uninstall commands after the user agrees. `mosaic hooks setup` installs supported agents found on PATH and skips missing agents.

4. Session restore evidence:

   ```bash
   ls -lh ~/.mosaicterm/*-hook-sessions.json 2>/dev/null
   ```

   Missing session stores usually means the agent has not run inside mosaic since hooks were installed, hooks are disabled, or the agent integration does not support resume capture.

5. Notification path:

   ```bash
   mosaic notify "mosaic diagnostic test"
   ```

   Use this only when the user is ready for a visible test notification.

## Interpretation

- `mosaic` not found: the CLI is not installed or not on PATH for this shell.
- `mosaic ping` fails: app is not reachable through the current socket path, the app is closed, or automation access is disabled.
- No `MOSAIC_WORKSPACE_ID` or `MOSAIC_SURFACE_ID`: the command is probably running outside a mosaic terminal. Some hooks intentionally no-op outside mosaic.
- Hook config exists but no session store: run one supported agent inside mosaic after installing hooks, then re-check.
- Session store exists but restore does not launch agents: check `terminal.autoResumeAgentSessions` and whether the saved executable still exists on PATH.
- Settings validation fails: fix the config first. Invalid config can make later symptoms misleading.

## Rules

- Stay read-only until the user asks to fix something.
- Never print raw hook files, session JSON, prompt logs, shell history, tokens, or API keys.
- Summarize file presence, size, modified time, and marker presence instead of contents.
- Prefer narrow fixes such as `mosaic hooks setup --agent codex` over reinstalling every integration.
- After a fix, rerun the diagnostic script and report the changed lines.
