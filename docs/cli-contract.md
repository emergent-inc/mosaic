# mosaic CLI Contract

This document is the compatibility contract for migrating `CLI/mosaic.swift` to
Swift ArgumentParser. The migration should preserve command names, aliases,
global flags, exit behavior, socket routing, and no-socket help behavior unless
a PR explicitly calls out an intentional contract change.

The current implementation is a hand-rolled parser. This spec is deliberately
written around user-visible behavior so the implementation can change behind it.

## Migration Rules

- Keep `mosaic --help`, `mosaic -h`, `mosaic --version`, and `mosaic -v` working without
  connecting to the mosaic socket.
- Keep documented `mosaic <command> --help` probes working without a socket where
  they already do.
- Keep `--socket`, `--password`, and `--window` as global options before the
  command. Keep presentation options `--json` and `--id-format` accepted either
  before or after the command.
- Keep UUIDs, refs such as `workspace:2`, and indexes accepted wherever the
  command accepts a window, workspace, pane, surface, or tab handle.
- Keep text output stable for scripting commands unless a command already
  documents JSON as the scripting interface.
- Keep hidden/internal commands available until their callers have migrated.

## Global Invocation

| Form | Contract |
| --- | --- |
| `mosaic <path>` | Open a directory or file parent in mosaic through the app's file-open path, without requiring control-socket access. Relative paths resolve from the current working directory. |
| `mosaic [global-options] <command> [options]` | Run a named command. Presentation options may appear before or after the command. |
| `mosaic --help`, `mosaic -h` | Print top-level usage without a socket. |
| `mosaic help` | Print top-level usage without a socket. |
| `mosaic --version`, `mosaic -v`, `mosaic version` | Print version summary without a socket. |

Global options:

| Option | Contract |
| --- | --- |
| `--socket <path>` | Override the socket path for this invocation. |
| `--password <value>` | Use an explicit socket password. Takes precedence over `MOSAIC_SOCKET_PASSWORD`. |
| `--json` | Prefer machine-readable JSON output for commands that support it. |
| `--id-format <refs\|uuids\|both>` | Select handle format in JSON and supported text output. |
| `--window <id\|ref\|index>` | Route the command through a specific window when supported. |

Environment:

| Variable | Contract |
| --- | --- |
| `MOSAIC_SOCKET_PATH` | Canonical socket path override. |
| `MOSAIC_SOCKET` | Deprecated compatibility alias for `MOSAIC_SOCKET_PATH`. New scripts should use `MOSAIC_SOCKET_PATH`; if both variables are set and differ, the CLI fails before socket commands. |
| `MOSAIC_SOCKET_PASSWORD` | Socket password fallback when `--password` is absent. |
| `MOSAIC_WORKSPACE_ID` | Default workspace context inside mosaic terminals. |
| `MOSAIC_SURFACE_ID` | Default surface context inside mosaic terminals. |
| `MOSAIC_TAB_ID` | Default tab context for tab commands. |

## Top-Level Commands

| Command | Contract |
| --- | --- |
| `welcome` | Print the welcome screen. |
| `docs` | Print canonical docs URLs, raw GitHub resources, and useful commands for a topic. |
| `settings` | Open Settings, print mosaic.json paths, or print settings docs. |
| `config` | Validate mosaic.json syntax, print config references, or reload config. |
| `shortcuts` | Open Settings to Keyboard Shortcuts. |
| `disable-browser` | Disable mosaic browser creation and link interception until re-enabled. |
| `enable-browser` | Re-enable mosaic browser creation and link interception. |
| `browser-status` | Print whether mosaic browser creation and link interception are enabled. |
| `agent-hibernation` | Enable or disable Agent Hibernation. |
| `restore-session` | Restore the previously saved mosaic session. |
| `open` | Open files, directories, or URLs in mosaic. |
| `feedback` | Open feedback UI or submit feedback with `--email`, `--body`, and repeated `--image`. |
| `feed` | Open the keyboard-first Feed TUI or manage persisted Feed workstream history. |
| `themes` | List, set, clear, or interactively pick Ghostty themes. |
| `claude-teams` | Launch Claude Code with mosaic/tmux-style agent team integration. |
| `codex-teams` | Launch Codex with mosaic-managed subagent panes. |
| `omo` | Launch OpenCode with oh-my-openagent integration. |
| `omx` | Launch Oh My Codex with mosaic pane integration. |
| `omc` | Launch Oh My Claude Code with mosaic pane integration. |
| `hooks` | Install, uninstall, and run agent hook integrations under one namespace. |
| `codex` | Compatibility alias for installing or uninstalling Codex hooks. |
| `ping` | Check socket connectivity. |
| `capabilities` | Print server capabilities as JSON. |
| `events` | Stream reconnectable mosaic events as newline-delimited JSON. |
| `auth` | Manage auth status, login, and logout through the app. |
| `vm`, `cloud` | Manage cloud VMs. `cloud` is an alias for `vm`. |
| `remotes`, `remote` | Manage remote Macs in the team device registry so they appear in the iOS app's device list. `remote` is an alias for `remotes`. |
| `rpc` | Call a raw v2 socket method with optional JSON params. |
| `identify` | Print server identity and caller context. |
| `list-windows` | List windows. |
| `current-window` | Print the selected window ID. |
| `new-window` | Create a new window. |
| `focus-window` | Focus a window by handle. |
| `close-window` | Close a window by handle. |
| `window displays` | List connected displays (name, index, main flag). |
| `window display <name\|index>` | Move the instance's window(s) onto a display by name (exact, substring) or index, preserving size. Does not steal focus. With `--window`, targets that window; otherwise moves all main windows. `--list` aliases `window displays`. |
| `window default-display [<name>\|--clear]` | Set, show (no arg), or clear (`--clear`) the shared, cross-tag default display that DEBUG dev builds open new windows on, stored in `~/.config/mosaic/mosaic.json` under `app.devWindowDisplay`. No running app required; applied at window creation. Also settable in Debug > Debug Windows > Dev Window Display. |
| `move-workspace-to-window` | Move a workspace into a target window. |
| `reorder-workspace` | Reorder a workspace inside a window. |
| `reorder-workspaces` | Atomically reorder workspaces inside pinned and unpinned groups. |
| `workspace-action` | Run workspace context-menu actions from the CLI. |
| `workspace` | Namespace for workspace verbs: `list`, `create`, `env`, `close`, `rename`, `select`, `reconnect`, `disconnect`, `group`. `workspace env` prints a workspace's configured environment variables (see [Workspace environment variables](#workspace-environment-variables)); pass `--mask` to redact the values. `workspace reconnect` manually reconnects a remote (SSH) workspace — including one whose automatic reconnect suspended because the host was unreachable — and `workspace disconnect` stops its remote connection. `env`, `reconnect`, and `disconnect` accept a positional workspace handle or `--workspace <id\|ref\|index>`, defaulting to the caller's workspace, then the selected one. |
| `move-tab-to-new-workspace` | Move a tab or surface into a newly created workspace. |
| `list-workspaces` | List workspaces. |
| `new-workspace` | Create a workspace, optionally with cwd, command, description, layout, and per-workspace environment variables (`--env KEY=VALUE` repeatable, `--env-file <path>`). See [Workspace environment variables](#workspace-environment-variables). |
| `ssh` | Open an SSH-backed workspace. Preserves the caller's live `SSH_AUTH_SOCK` for app-launched OpenSSH processes so `ForwardAgent yes` from ssh_config works normally. Supports `-A` / `--forward-agent` to request forwarding and `-a` / `--no-forward-agent` to disable forwarding for a workspace. Agent forwarding remains opt-in because forwarded agents can be used by processes on the remote host while the SSH session is active. |
| `remote-daemon-status` | Print bundled remote daemon version, asset, checksum, and cache status. |
| `ssh-session-list` | List persisted SSH PTY sessions for one remote workspace or all remote workspaces. Supports `--json`. |
| `ssh-session-attach` | Create a local terminal surface that reattaches to an existing persisted SSH PTY session. |
| `ssh-session-cleanup` | Close one or all persisted SSH PTY sessions. Supports `--json`. |
| `new-split` | Split from a surface in a direction. |
| `list-panes` | List panes in a workspace. |
| `list-pane-surfaces` | List surfaces in a pane. |
| `tree` | Print a window, workspace, pane, and surface tree. |
| `top` | Print process/resource usage for mosaic windows, workspaces, panes, and surfaces. |
| `focus-pane` | Focus a pane. |
| `new-pane` | Create a pane with terminal or browser content. |
| `new-surface` | Create a surface inside a pane. |
| `close-surface` | Close a surface. |
| `move-surface` | Move a surface to another pane, workspace, window, or index. |
| `split-off` | Move a surface into a new split without changing focus by default. |
| `reorder-surface` | Reorder a surface within its pane. |
| `tab-action` | Run horizontal tab context-menu actions. |
| `rename-tab` | Rename a tab. Compatibility wrapper for `tab-action rename`. |
| `drag-surface-to-split` | Move a surface into a split direction. |
| `refresh-surfaces` | Ask the app to refresh terminal surfaces. |
| `reload-config` | Ask mosaic to reload configuration. |
| `surface-health` | Print terminal surface health information. |
| `debug-terminals` | Print debug terminal state. |
| `trigger-flash` | Trigger a visual flash on a workspace or surface. |
| `list-panels` | List panels. Compatibility alias over pane/surface data. |
| `focus-panel` | Focus a panel. Compatibility alias over surface focus. |
| `close-workspace` | Close a workspace. |
| `select-workspace` | Select a workspace. |
| `rename-workspace`, `rename-window` | Rename a workspace. `rename-window` is a compatibility alias. |
| `current-workspace` | Print current workspace information. |
| `read-screen` | Read terminal text from a surface. |
| `send` | Send text to a terminal surface. |
| `send-key` | Send one key to a terminal surface. |
| `send-panel` | Send text to a panel/surface. |
| `send-key-panel` | Send one key to a panel/surface. |
| `notify` | Send a notification to a workspace/surface. |
| `list-notifications` | List queued notifications, including `created_at` and `tab_title`. |
| `dismiss-notification` | Remove one notification, or remove already-read notifications with `--all-read`. |
| `mark-notification-read` | Mark one notification, a workspace/surface scope, or all notifications read. |
| `open-notification` | Focus the notification's workspace/surface and mark it read. |
| `jump-to-unread` | Focus the latest unread notification. |
| `clear-notifications` | Clear queued notifications. |
| `right-sidebar` | Control right sidebar visibility, mode, focus, and state reads. |
| `set-status` | Set a sidebar status pill. |
| `clear-status` | Remove a sidebar status pill. |
| `list-status` | List sidebar status pills. |
| `set-progress` | Set sidebar progress. |
| `clear-progress` | Clear sidebar progress. |
| `log` | Append a sidebar log entry. |
| `clear-log` | Clear sidebar log entries. |
| `list-log` | List sidebar log entries. |
| `sidebar-state` | Dump sidebar metadata state. |
| `claude-hook` | Compatibility alias for Claude Code hook events from stdin JSON. |
| `set-app-focus` | Override app focus state for tests. |
| `simulate-app-active` | Trigger app-active handling for tests. |
| `browser` | Run browser automation commands. |
| `open-browser` | Legacy alias for `browser open`. |
| `navigate` | Legacy alias for `browser navigate`. |
| `browser-back` | Legacy alias for `browser back`. |
| `browser-forward` | Legacy alias for `browser forward`. |
| `browser-reload` | Legacy alias for `browser reload`. |
| `get-url` | Legacy alias for `browser get-url`. |
| `focus-webview` | Legacy alias for `browser focus-webview`. |
| `is-webview-focused` | Legacy alias for `browser is-webview-focused`. |
| `markdown` | Open a markdown file in a formatted viewer panel with live reload. |
| `vm-pty-attach` | Internal VM PTY attach command. |
| `vm-ssh-attach` | Hidden compatibility alias for older VM workspaces. |
| `vm-pty-connect` | Internal helper that connects to a VM PTY from a config file. |
| `ssh-pty-attach` | Internal helper used by SSH terminal startup scripts to bridge a local terminal surface to a remote PTY session. |
| `ssh-session-end` | Internal helper that clears remote SSH session state. |
| `__tmux-compat` | Internal tmux compatibility dispatcher. |

## Command Families

Auth subcommands:

| Command | Contract |
| --- | --- |
| `auth status` | Print signed-in state. Supports `--json`. |
| `auth login` | Begin sign-in through the app and wait for completion. |
| `auth logout` | Clear the current session. |

VM subcommands:

| Command | Contract |
| --- | --- |
| `vm ls`, `vm list` | List VMs. |
| `vm new`, `vm create` | Create a VM. Supports `--image`, `--provider`, `--detach`, and `-d`. |
| `vm shell`, `vm attach` | Open an interactive shell for an existing VM. |
| `vm rm`, `vm destroy`, `vm delete` | Destroy a VM. |
| `vm ssh` | Open a mosaic-managed SSH workspace for an existing VM. |
| `vm ssh-info` | Print SSH connection info. |
| `vm ssh-attach` | Internal attach helper. |
| `vm exec` | Run a shell command inside a VM. |

Remotes subcommands:

| Command | Contract |
| --- | --- |
| `remotes list`, `remotes ls` | List the team's registered remotes (name, deviceId, routes, tag, last seen). Supports `--json`. |
| `remotes add <name>` | Register or update a remote with one or more `--route <host:port>`. Supports `--tag` and `--json`. Idempotent on `<name>` (re-adding updates routes). The host must be a Tailscale address the phone can authenticate to (CGNAT `100.64.x.x`-`100.127.x.x` or `*.ts.net`); loopback, plain LAN IPs, and bare hostnames are rejected. |
| `remotes remove <name-or-deviceId>` | Remove a remote you registered. Aliases `rm`, `delete`. Supports `--json`. |

Theme subcommands:

| Command | Contract |
| --- | --- |
| `themes` | List available themes and report the managed current theme. |
| `themes list` | List available themes and mark `Anysphere Dark` as the managed terminal theme. |
| `themes set <theme>` | Disabled; terminal colors are fixed to `Anysphere Dark`. |
| `themes set --light <theme>` | Disabled; terminal colors are fixed to `Anysphere Dark`. |
| `themes set --dark <theme>` | Disabled; terminal colors are fixed to `Anysphere Dark`. |
| `themes clear` | Disabled; terminal colors are fixed to `Anysphere Dark`. |

Workspace and tab action names:

| Command | Actions |
| --- | --- |
| `workspace-action` | `pin`, `unpin`, `rename`, `clear-name`, `set-description`, `clear-description`, `move-up`, `move-down`, `move-top`, `close-others`, `close-above`, `close-below`, `mark-read`, `mark-unread`, `set-color`, `clear-color` |
| `tab-action` | `rename`, `clear-name`, `close-left`, `close-right`, `close-others`, `new-terminal-right`, `new-browser-right`, `reload`, `duplicate`, `pin`, `unpin`, `mark-unread` |

### Workspace environment variables

A workspace can carry a set of user-defined environment variables that every
shell spawned in it inherits.

Setting them:

- CLI: `mosaic new-workspace --env KEY=VALUE [--env ...] [--env-file <path>]`
  (and the same flags on `mosaic workspace create`). `--env` is repeatable;
  `--env-file` reads `KEY=VALUE` lines (blank lines and `#` comments ignored, an
  optional leading `export ` stripped). When both are given, `--env` overrides a
  value from a file.
- Project config (`mosaic.json`): an `env` object on a workspace definition, e.g.
  `{ "name": "Build", "cwd": ".", "env": { "AWS_PROFILE": "prod" } }`.
- Socket: the `workspace_env` param on `workspace.create`.

Inspecting them: `mosaic workspace env [<handle>] [--mask] [--json]` prints the
configured set. `--mask` redacts the values so secrets are not echoed in full.
The env set is intentionally omitted from `workspace list` output so a plain
listing never leaks secrets.

Semantics:

- **Inheritance.** The variables apply to the workspace's initial shell and to
  every pane, surface, and split created later in that workspace — no per-pane
  re-export. They are also re-applied to every shell recreated on session
  restore.
- **Persistence.** They are stored on the workspace in the session manifest, so
  they survive app restart, daemon restart, and session restore.
- **Precedence.** Workspace env overlays the inherited process environment. It is
  applied as the shell's startup environment, so it is visible to login-shell
  init files (`~/.zprofile`, `~/.zshrc`) as they run, but any `export` those
  files perform for the same key wins for the interactive session (they run after
  the variable is seeded). An explicit per-surface environment (a layout
  `surfaces[].env`, SSH startup env) overrides the workspace value for that
  surface.
- **Protected `MOSAIC_*` variables.** Workspace env can never override the managed
  variables mosaic injects (e.g. `MOSAIC_WORKSPACE_ID`, `MOSAIC_SURFACE_ID`,
  `MOSAIC_SOCKET_PATH`, `MOSAIC_SOCKET_PASSWORD`) or the terminal identity variables
  (`TERM`, `COLORTERM`, `TERM_PROGRAM`); those keys are protected at spawn time
  and silently win.
- **Secrets.** Values may be secrets. They are never logged, are masked by
  `--mask`, and are kept out of `workspace list`. Prefer `--env-file` so secrets
  do not land in shell history. Note that values stored in the session manifest
  live on disk in plaintext.

tmux compatibility commands:

| Command | Contract |
| --- | --- |
| `capture-pane` | Read pane text. |
| `resize-pane` | Resize a pane with direction flags. |
| `pipe-pane` | Pipe pane text to a shell command. |
| `wait-for` | Signal or wait on a named synchronization point. |
| `swap-pane` | Swap two panes. |
| `break-pane` | Move a pane into a new workspace. |
| `join-pane` | Join a pane into another pane. |
| `next-window`, `previous-window`, `last-window` | Move workspace selection. |
| `last-pane` | Focus the last pane. |
| `find-window` | Find a workspace by title or content. |
| `clear-history` | Clear terminal scrollback. |
| `set-hook` | Manage tmux-compat hook definitions. |
| `popup` | Placeholder, currently unsupported. |
| `bind-key`, `unbind-key`, `copy-mode` | Placeholders, currently unsupported. |
| `set-buffer` | Set a tmux-compat buffer. |
| `paste-buffer` | Paste a tmux-compat buffer. |
| `list-buffers` | List tmux-compat buffers. |
| `respawn-pane` | Send a restart command to a surface. |
| `display-message` | Print or display a message. |

Browser subcommands:

| Command | Contract |
| --- | --- |
| `browser open`, `browser open-split`, `browser new` | Create or open a browser surface. |
| `browser goto`, `browser navigate` | Navigate to a URL. |
| `browser back`, `browser forward`, `browser reload` | Navigate browser history or reload. |
| `browser url`, `browser get-url` | Print current URL. |
| `browser focus-webview`, `browser is-webview-focused` | Focus or query webview focus. |
| `browser snapshot` | Print a DOM snapshot. |
| `browser eval` | Evaluate JavaScript. |
| `browser wait` | Wait for selector, text, URL, load state, or JS predicate. |
| `browser click`, `browser dblclick`, `browser hover`, `browser focus`, `browser check`, `browser uncheck`, `browser scroll-into-view` | Run element interaction. |
| `browser type`, `browser fill` | Type into or set an input. |
| `browser press`, `browser key`, `browser keydown`, `browser keyup` | Send keyboard input. |
| `browser select` | Select an option. |
| `browser scroll` | Scroll page or element. |
| `browser screenshot` | Save a screenshot. |
| `browser get` | Read URL, title, text, HTML, value, attr, count, box, or styles. |
| `browser is` | Check visible, enabled, or checked state. |
| `browser find` | Find by role, text, label, placeholder, alt, title, testid, first, last, or nth. |
| `browser frame` | Select frame context. |
| `browser dialog` | Accept or dismiss dialogs. |
| `browser download` | Wait for or save downloads. |
| `browser profiles` | List, add, rename, clear, or delete mosaic browser profiles. `clear` refuses to wipe active profiles unless `--force` is passed. |
| `browser import` | Open the browser import wizard. In detected coding-agent environments, defaults to non-interactive cookie import; pass `--interactive` to force the wizard. Non-interactive import supports `--from`, `--profile`, `--all-profiles`, `--to-profile`, `--create-profile`, and `--domain`. |
| `browser cookies` | Get, set, or clear cookies. |
| `browser storage` | Get, set, or clear local/session storage. |
| `browser tab` | Create, list, switch, or close browser tabs. |
| `browser console`, `browser errors` | List or clear console messages and errors. |
| `browser highlight` | Highlight an element. |
| `browser state` | Save or load browser state. |
| `browser addinitscript`, `browser addscript`, `browser addstyle` | Inject scripts or CSS. |
| `browser viewport` | Set viewport size. |
| `browser geolocation`, `browser geo` | Set geolocation. |
| `browser offline` | Toggle offline state. |
| `browser trace` | Start or stop trace capture. |
| `browser network` | Route, unroute, or list requests. |
| `browser screencast` | Start or stop screencast. |
| `browser input`, `browser input_mouse`, `browser input_keyboard`, `browser input_touch` | Send low-level input. |
| `browser identify` | Identify browser surface context. |

Hook subcommands:

| Command | Contract |
| --- | --- |
| `hooks setup` | Install hooks for all supported agents whose binaries are on `PATH`. Supports `--agent <name>`, positional agent filters such as `mosaic hooks setup rovo`, and `--yes`. |
| `hooks uninstall` | Remove hooks for all supported agents. Supports `--agent <name>`, positional agent filters such as `mosaic hooks uninstall rovo`, and `--yes`. |
| `hooks <agent> install` | Install hooks for one supported agent. `opencode` also supports `--project` for the project-local Feed plugin. |
| `hooks <agent> uninstall` | Remove hooks for one supported agent. |
| `hooks claude <event>` | Handle Claude Code hook events. `claude-hook <event>` remains as the main-compatibility alias. |
| `hooks codex <event>` | Handle Codex hook events. `codex install-hooks` remains as the main-compatibility installer alias. |
| `hooks feed --source <agent>` | Convert agent hook events into Feed context. |
| `hooks <agent> <event>` | Generic hook surface for `grok`, `opencode`, `pi`, `amp`, `cursor`, `gemini`, `rovodev`, `copilot`, `codebuddy`, `factory`, and `qoder`. |

Right sidebar commands:

| Command | Contract |
| --- | --- |
| `right-sidebar toggle`, `right-sidebar show`, `right-sidebar hide` | Change right-sidebar visibility without printing on success. |
| `right-sidebar focus` | Focus the current right-sidebar mode. |
| `right-sidebar set <files\|find\|vault\|sessions\|feed\|dock>` | Show the right sidebar, switch mode, and focus it unless `--no-focus` is passed. |
| `right-sidebar files`, `right-sidebar find`, `right-sidebar vault`, `right-sidebar sessions`, `right-sidebar feed`, `right-sidebar dock` | Short aliases for `right-sidebar set <mode>` with focus. |
| `right-sidebar mode` | Print JSON with `visible` and `mode`. |
| `--workspace <id\|ref\|index>` | Target the window containing a workspace. Refs and indexes resolve before the V1 socket command is sent. |
| `--window <id\|ref\|index>` | Target a window. Refs and indexes resolve before the V1 socket command is sent. |
| `--no-focus` | Only valid with `set`; switches mode without moving focus. |

Custom sidebar commands:

| Command | Contract |
| --- | --- |
| `sidebar validate [name]` | Validate all custom sidebars, or one named sidebar, under `~/.config/mosaic/sidebars`. |
| `sidebar reload [name]` | Validate all custom sidebars, then request a reload for every valid one. |
| `sidebar select <name>` | Validate and activate one custom sidebar in the sidebar picker. |
| `sidebar open <name>` | Validate and open one custom sidebar as a normal Bonsplit pane tab, preferring the right-side split from the focused surface. |

Docs topics:

| Command | Contract |
| --- | --- |
| `docs` | List docs topics without a socket. |
| `docs settings` | Print the configuration docs URL, raw schema URL, mosaic.json paths, backup reminder, and reload command. |
| `docs shortcuts` | Print shortcut docs and raw shortcut data resources. |
| `docs api` | Print API docs and raw CLI contract resources. |
| `docs browser` | Print browser automation docs and raw browser skill resources. |
| `docs agents` | Print agent integration docs and raw integration resources. |

Settings subcommands:

| Command | Contract |
| --- | --- |
| `settings` | Open the Settings window, launching mosaic if needed. |
| `settings open [target]` | Open Settings to an optional target section. |
| `settings path` | Print mosaic.json paths, docs URL, schema URL, backup reminder, and reload command without a socket. |
| `settings docs` | Print the same output as `docs settings` without a socket. |
| `settings <target>` | Open Settings to a target section. Supported aliases include `shortcuts`, `json`, `mosaic-json`, `browser`, and `automation`. |

Config subcommands:

| Command | Contract |
| --- | --- |
| `config doctor [--path <file>]`, `config check`, `config validate` | Validate JSONC syntax for config files. When `--path` is absent, default discovery checks the primary config, project-level `.mosaic/mosaic.json` or `mosaic.json`, and legacy config files. `--path <file>` may be repeated to validate multiple explicit files. Exits 0 on success and 1 on any error. Supports `--json`. Works without a socket. |
| `config path`, `config paths` | Print mosaic.json paths, docs URL, schema URL, backup reminder, and reload command without a socket. |
| `config docs`, `config documentation` | Print the same output as `docs settings` without a socket. |
| `config reload` | Ask the running mosaic app to reload configuration. Requires a socket. |
| `config get sidebar-font-size` | Print the effective sidebar text size. |
| `config set sidebar-font-size <points>` | Write the sidebar text size to mosaic's editable Ghostty config and reload the running app when available. |
| `config sidebar-font-size [points]` | Get the sidebar text size, or set it when a point size is provided. |
| `config get surface-tab-bar-font-size` | Print the effective workspace tab bar text size. |
| `config set surface-tab-bar-font-size <points>` | Write the workspace tab bar text size to mosaic's editable Ghostty config and reload the running app when available. |
| `config surface-tab-bar-font-size [points]` | Get the workspace tab bar text size, or set it when a point size is provided. |
| `config get <key>`, `config set <key> <points>` | Generic get/set for `sidebar-font-size` and `surface-tab-bar-font-size`. |

`config doctor --json` outputs an object with `ok`, `error_count`,
`findings`, `reload_command`, `docs_url`, and `schema_url`. Each finding includes
`label`, `display_path`, `path`, `status`, `ok`, `keys`, and, when available,
`message` and `bytes`.

Events command:

| Option | Contract |
| --- | --- |
| `--after <seq>`, `--after-seq <seq>` | Subscribe to retained events after a sequence number. |
| `--cursor-file <path>` | Read the starting sequence from a file and update it after every event. |
| `--name <event>` | Filter by event name. Repeatable. |
| `--category <name>` | Filter by category. Repeatable. |
| `--reconnect` | Reconnect and resume from the last received sequence until interrupted. |
| `--limit <n>` | Exit after printing `n` event frames. |
| `--no-ack` | Suppress the initial ack frame in stdout. |
| `--no-heartbeat`, `--no-heartbeats` | Suppress heartbeat frames in stdout. |

`events.stream` is a v2 socket method advertised by `capabilities`. The first
response frame is an `ack`; sequence resume metadata lives under `ack.resume` as
`after_seq`, `oldest_seq`, `latest_seq`, `next_seq`, and `gap`. Event frames
carry a process-local monotonic `seq` and a stable `id` for dedupe. Clients
should persist `seq` after processing each event and reconnect with that value.
See [events.md](events.md) for the full protocol and event catalog. Every emitted event is also appended to
`~/.mosaicterm/events.jsonl`, including model lifecycle events for window
creation, close, focus, key-window state, workspace selection, pane focus, and
surface selection, focus, creation, or closure. The stream is bounded: mosaic keeps
4,096 replay events in memory, caps each encoded event frame at 16 KiB, closes
slow subscribers after 1,024 pending events, and rotates `events.jsonl` with one
16 MiB archive at `events.jsonl.1`.

## No-Socket Help Probes

The following probes are executable contract checks. They must exit 0 and print
the expected text without connecting to a mosaic socket.

<!-- cli-contract-help-probes:start -->
- `mosaic --help` -> `mosaic - control mosaic via Unix socket`
- `mosaic --help` -> `open <path-or-url>...`
- `mosaic help` -> `mosaic - control mosaic via Unix socket`
- `mosaic ping --help` -> `Usage: mosaic ping`
- `mosaic capabilities --help` -> `Usage: mosaic capabilities`
- `mosaic events --help` -> `Usage: mosaic events [options]`
- `mosaic auth --help` -> `Usage: mosaic auth <status|login|logout>`
- `mosaic vm --help` -> `Usage: mosaic vm <new|ls|rm|exec|shell|attach|ssh|ssh-info> [args...]`
- `mosaic cloud --help` -> `Usage: mosaic cloud <new|ls|rm|exec|shell|attach|ssh|ssh-info> [args...]`
- `mosaic remotes --help` -> `Usage: mosaic remotes <list|add|remove> [options]`
- `mosaic remote --help` -> `Usage: mosaic remotes <list|add|remove> [options]`
- `mosaic rpc --help` -> `Usage: mosaic rpc <method> [json-params]`
- `mosaic help --help` -> `Usage: mosaic help`
- `mosaic docs --help` -> `Usage: mosaic docs [settings|shortcuts|api|browser|agents|dock]`
- `mosaic docs` -> `Topics:`
- `mosaic docs settings` -> `Config files:`
- `mosaic docs dock` -> `dock: Custom right-sidebar terminal controls`
- `mosaic settings --help` -> `Usage: mosaic settings [open [target]|path|docs|<target>]`
- `mosaic settings path` -> `Config files:`
- `mosaic settings docs` -> `Config files:`
- `mosaic config --help` -> `Usage: mosaic config <doctor|check|validate|path|paths|docs|documentation|reload|get|set|sidebar-font-size|surface-tab-bar-font-size>`
- `mosaic config path` -> `Config files:`
- `mosaic config docs` -> `Config files:`
- `mosaic welcome --help` -> `Usage: mosaic welcome`
- `mosaic welcome` -> `Toggle Left Sidebar`
- `mosaic welcome` -> `Toggle Right Sidebar`
- `mosaic shortcuts --help` -> `Usage: mosaic shortcuts`
- `mosaic disable-browser --help` -> `Usage: mosaic disable-browser [--json]`
- `mosaic enable-browser --help` -> `Usage: mosaic enable-browser [--json]`
- `mosaic browser-status --help` -> `Usage: mosaic browser-status [--json]`
- `mosaic agent-hibernation --help` -> `Usage: mosaic agent-hibernation <on|off> [--json]`
- `mosaic restore-session --help` -> `Usage: mosaic restore-session`
- `mosaic open --help` -> `Usage: mosaic open <path-or-url>...`
- `mosaic feedback --help` -> `Usage: mosaic feedback`
- `mosaic feed --help` -> `Usage: mosaic feed tui [--opentui|--legacy]`
- `mosaic hooks --help` -> `Usage: mosaic hooks setup [agent] [--agent <name>] [--yes|-y]`
- `mosaic codex --help` -> `Usage: mosaic codex <install-hooks|uninstall-hooks>`
- `mosaic themes --help` -> `Usage: mosaic themes`
- `mosaic omo --help` -> `Usage: mosaic omo [opencode-args...]`
- `mosaic omx --help` -> `Usage: mosaic omx [omx-args...]`
- `mosaic omc --help` -> `Usage: mosaic omc [omc-args...]`
- `mosaic identify --help` -> `Usage: mosaic identify`
- `mosaic list-windows --help` -> `Usage: mosaic list-windows`
- `mosaic current-window --help` -> `Usage: mosaic current-window`
- `mosaic new-window --help` -> `Usage: mosaic new-window`
- `mosaic focus-window --help` -> `Usage: mosaic focus-window --window <id|ref|index>`
- `mosaic close-window --help` -> `Usage: mosaic close-window --window <id|ref|index>`
- `mosaic move-workspace-to-window --help` -> `Usage: mosaic move-workspace-to-window`
- `mosaic move-surface --help` -> `Usage: mosaic move-surface`
- `mosaic split-off --help` -> `Usage: mosaic split-off`
- `mosaic reorder-surface --help` -> `Usage: mosaic reorder-surface`
- `mosaic reorder-workspace --help` -> `Usage: mosaic reorder-workspace`
- `mosaic reorder-workspaces --help` -> `Usage: mosaic reorder-workspaces`
- `mosaic workspace-action --help` -> `Usage: mosaic workspace-action --action <name>`
- `mosaic move-tab-to-new-workspace --help` -> `Usage: mosaic move-tab-to-new-workspace`
- `mosaic tab-action --help` -> `Usage: mosaic tab-action --action <name>`
- `mosaic rename-tab --help` -> `Usage: mosaic rename-tab`
- `mosaic new-workspace --help` -> `Usage: mosaic new-workspace`
- `mosaic list-workspaces --help` -> `Usage: mosaic list-workspaces`
- `mosaic ssh --help` -> `Usage: mosaic ssh <destination>`
- `mosaic ssh --help` -> `--forward-agent`
- `mosaic ssh-session-list --help` -> `Usage: mosaic ssh-session-list`
- `mosaic ssh-session-attach --help` -> `Usage: mosaic ssh-session-attach --session-id <id>`
- `mosaic ssh-session-cleanup --help` -> `Usage: mosaic ssh-session-cleanup`
- `mosaic new-split --help` -> `Usage: mosaic new-split`
- `mosaic list-panes --help` -> `Usage: mosaic list-panes`
- `mosaic list-pane-surfaces --help` -> `Usage: mosaic list-pane-surfaces`
- `mosaic tree --help` -> `Usage: mosaic tree`
- `mosaic top --help` -> `Usage: mosaic top`
- `mosaic focus-pane --help` -> `Usage: mosaic focus-pane`
- `mosaic new-pane --help` -> `Usage: mosaic new-pane`
- `mosaic new-surface --help` -> `Usage: mosaic new-surface`
- `mosaic close-surface --help` -> `Usage: mosaic close-surface`
- `mosaic drag-surface-to-split --help` -> `Usage: mosaic drag-surface-to-split`
- `mosaic refresh-surfaces --help` -> `Usage: mosaic refresh-surfaces`
- `mosaic reload-config --help` -> `Usage: mosaic reload-config`
- `mosaic surface-health --help` -> `Usage: mosaic surface-health`
- `mosaic debug-terminals --help` -> `Usage: mosaic debug-terminals`
- `mosaic trigger-flash --help` -> `Usage: mosaic trigger-flash`
- `mosaic list-panels --help` -> `Usage: mosaic list-panels`
- `mosaic focus-panel --help` -> `Usage: mosaic focus-panel`
- `mosaic close-workspace --help` -> `Usage: mosaic close-workspace`
- `mosaic select-workspace --help` -> `Usage: mosaic select-workspace`
- `mosaic rename-workspace --help` -> `Usage: mosaic rename-workspace`
- `mosaic rename-window --help` -> `Usage: mosaic rename-workspace`
- `mosaic current-workspace --help` -> `Usage: mosaic current-workspace`
- `mosaic capture-pane --help` -> `Usage: mosaic capture-pane`
- `mosaic resize-pane --help` -> `Usage: mosaic resize-pane`
- `mosaic pipe-pane --help` -> `Usage: mosaic pipe-pane`
- `mosaic wait-for --help` -> `Usage: mosaic wait-for`
- `mosaic swap-pane --help` -> `Usage: mosaic swap-pane`
- `mosaic break-pane --help` -> `Usage: mosaic break-pane`
- `mosaic join-pane --help` -> `Usage: mosaic join-pane`
- `mosaic next-window --help` -> `Usage: mosaic next-window`
- `mosaic previous-window --help` -> `Usage: mosaic previous-window`
- `mosaic last-window --help` -> `Usage: mosaic last-window`
- `mosaic last-pane --help` -> `Usage: mosaic last-pane`
- `mosaic find-window --help` -> `Usage: mosaic find-window`
- `mosaic clear-history --help` -> `Usage: mosaic clear-history`
- `mosaic set-hook --help` -> `Usage: mosaic set-hook`
- `mosaic popup --help` -> `Usage: mosaic popup`
- `mosaic bind-key --help` -> `Usage: mosaic bind-key`
- `mosaic unbind-key --help` -> `Usage: mosaic unbind-key`
- `mosaic copy-mode --help` -> `Usage: mosaic copy-mode`
- `mosaic set-buffer --help` -> `Usage: mosaic set-buffer`
- `mosaic paste-buffer --help` -> `Usage: mosaic paste-buffer`
- `mosaic list-buffers --help` -> `Usage: mosaic list-buffers`
- `mosaic respawn-pane --help` -> `Usage: mosaic respawn-pane`
- `mosaic display-message --help` -> `Usage: mosaic display-message`
- `mosaic read-screen --help` -> `Usage: mosaic read-screen`
- `mosaic send --help` -> `Usage: mosaic send`
- `mosaic send-key --help` -> `Usage: mosaic send-key`
- `mosaic send-panel --help` -> `Usage: mosaic send-panel`
- `mosaic send-key-panel --help` -> `Usage: mosaic send-key-panel`
- `mosaic notify --help` -> `Usage: mosaic notify`
- `mosaic list-notifications --help` -> `Usage: mosaic list-notifications`
- `mosaic dismiss-notification --help` -> `Usage: mosaic dismiss-notification`
- `mosaic mark-notification-read --help` -> `Usage: mosaic mark-notification-read`
- `mosaic open-notification --help` -> `Usage: mosaic open-notification`
- `mosaic jump-to-unread --help` -> `Usage: mosaic jump-to-unread`
- `mosaic clear-notifications --help` -> `Usage: mosaic clear-notifications`
- `mosaic right-sidebar --help` -> `Usage: mosaic right-sidebar <command> [flags]`
- `mosaic set-status --help` -> `Usage: mosaic set-status`
- `mosaic clear-status --help` -> `Usage: mosaic clear-status`
- `mosaic list-status --help` -> `Usage: mosaic list-status`
- `mosaic set-progress --help` -> `Usage: mosaic set-progress`
- `mosaic clear-progress --help` -> `Usage: mosaic clear-progress`
- `mosaic log --help` -> `Usage: mosaic log`
- `mosaic clear-log --help` -> `Usage: mosaic clear-log`
- `mosaic list-log --help` -> `Usage: mosaic list-log`
- `mosaic sidebar-state --help` -> `Usage: mosaic sidebar-state`
- `mosaic set-app-focus --help` -> `Usage: mosaic set-app-focus`
- `mosaic simulate-app-active --help` -> `Usage: mosaic simulate-app-active`
- `mosaic claude-hook --help` -> `Usage: mosaic claude-hook`
- `mosaic browser --help` -> `Usage: mosaic browser`
- `mosaic open-browser --help` -> `Legacy alias for 'mosaic browser open'`
- `mosaic navigate --help` -> `Legacy alias for 'mosaic browser navigate'`
- `mosaic browser-back --help` -> `Legacy alias for 'mosaic browser back'`
- `mosaic browser-forward --help` -> `Legacy alias for 'mosaic browser forward'`
- `mosaic browser-reload --help` -> `Legacy alias for 'mosaic browser reload'`
- `mosaic get-url --help` -> `Legacy alias for 'mosaic browser get-url'`
- `mosaic focus-webview --help` -> `Legacy alias for 'mosaic browser focus-webview'`
- `mosaic is-webview-focused --help` -> `Legacy alias for 'mosaic browser is-webview-focused'`
- `mosaic markdown --help` -> `Usage: mosaic markdown open <path>`
<!-- cli-contract-help-probes:end -->

## No-Socket Negative Help Probes

The following probes must not print help. They protect argument forwarding after
`--`, where a forwarded `--help` token belongs to the command payload.

<!-- cli-contract-negative-help-probes:start -->
- `mosaic vm exec demo -- --help` !> `Usage: mosaic vm`
<!-- cli-contract-negative-help-probes:end -->

## Current Help Caveats

These are current contracts to preserve until a follow-up PR intentionally
changes them:

- `mosaic version --help` currently prints the version summary because `version`
  is handled before subcommand help dispatch.
- `mosaic claude-teams --help` is handled by the command launcher, not by the
  pre-socket help dispatcher.
- `mosaic codex-teams --help` is handled by the command launcher, not by the
  pre-socket help dispatcher.
- `mosaic remote-daemon-status --help` currently prints status because the command
  runs before subcommand help dispatch.

## ArgumentParser Migration Sequence

1. Keep this contract file and `tests/test_cli_contract_help.py` green.
2. Add Swift ArgumentParser as a dependency without changing behavior.
3. Introduce a parse-only facade that maps ArgumentParser command structs onto
   existing `MosaicCLI` runner methods.
4. Move one command family at a time into small files, starting with no-socket
   commands (`version`, `themes`, hook installers), then socket commands, then
   browser and tmux compatibility.
5. After each family moves, run the contract probes plus targeted socket tests in
   GitHub Actions.
6. When all command families are migrated, remove the manual global parser and
   legacy helper code that no longer owns behavior.
