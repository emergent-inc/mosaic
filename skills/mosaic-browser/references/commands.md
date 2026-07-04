# Command Reference (mosaic Browser)

This maps common `agent-browser` usage to `mosaic browser` usage.

## Direct Equivalents

- `agent-browser open <url>` -> `mosaic browser open <url>`
- `agent-browser goto|navigate <url>` -> `mosaic browser <surface> goto|navigate <url>`
- `agent-browser snapshot -i` -> `mosaic browser <surface> snapshot --interactive`
- `agent-browser click <ref>` -> `mosaic browser <surface> click <ref>`
- `agent-browser fill <ref> <text>` -> `mosaic browser <surface> fill <ref> <text>`
- `agent-browser type <ref> <text>` -> `mosaic browser <surface> type <ref> <text>`
- `agent-browser select <ref> <value>` -> `mosaic browser <surface> select <ref> <value>`
- `agent-browser get text <ref>` -> `mosaic browser <surface> get text <ref-or-selector>`
- `agent-browser get url` -> `mosaic browser <surface> get url`
- `agent-browser get title` -> `mosaic browser <surface> get title`

## Core Command Groups

### Navigation

```bash
mosaic browser open <url>                        # opens in caller's workspace (uses MOSAIC_WORKSPACE_ID)
mosaic browser open <url> --workspace <id|ref>   # opens in a specific workspace
mosaic browser <surface> goto <url>
mosaic browser <surface> back|forward|reload
mosaic browser <surface> get url|title
```

> **Workspace context:** `browser open` targets the workspace of the terminal where the command is run (via `MOSAIC_WORKSPACE_ID`), even if a different workspace is currently focused. Use `--workspace` to override.

### Snapshot and Inspection

```bash
mosaic browser <surface> snapshot --interactive
mosaic browser <surface> snapshot --interactive --compact --max-depth 3
mosaic browser <surface> get text body
mosaic browser <surface> get html body
mosaic browser <surface> get value "#email"
mosaic browser <surface> get attr "#email" --attr placeholder
mosaic browser <surface> get count ".row"
mosaic browser <surface> get box "#submit"
mosaic browser <surface> get styles "#submit" --property color
mosaic browser <surface> eval '<js>'
```

### Interaction

```bash
mosaic browser <surface> click|dblclick|hover|focus <selector-or-ref>
mosaic browser <surface> fill <selector-or-ref> [text]   # empty text clears
mosaic browser <surface> type <selector-or-ref> <text>
mosaic browser <surface> press|keydown|keyup <key>
mosaic browser <surface> select <selector-or-ref> <value>
mosaic browser <surface> check|uncheck <selector-or-ref>
mosaic browser <surface> scroll [--selector <css>] [--dx <n>] [--dy <n>]
```

### Wait

```bash
mosaic browser <surface> wait --selector "#ready" --timeout-ms 10000
mosaic browser <surface> wait --text "Done" --timeout-ms 10000
mosaic browser <surface> wait --url-contains "/dashboard" --timeout-ms 10000
mosaic browser <surface> wait --load-state complete --timeout-ms 15000
mosaic browser <surface> wait --function "document.readyState === 'complete'" --timeout-ms 10000
```

### Session/State

```bash
mosaic browser <surface> cookies get|set|clear ...
mosaic browser <surface> storage local|session get|set|clear ...
mosaic browser <surface> tab list|new|switch|close ...
mosaic browser <surface> state save|load <path>
```

### Diagnostics

```bash
mosaic browser <surface> console list|clear
mosaic browser <surface> errors list|clear
mosaic browser <surface> highlight <selector>
mosaic browser <surface> screenshot
mosaic browser <surface> download wait --timeout-ms 10000
```

## Agent Reliability Tips

- Use `--snapshot-after` on mutating actions to return a fresh post-action snapshot.
- Re-snapshot after navigation, modal open/close, or major DOM changes.
- Prefer short handles in outputs by default (`surface:N`, `pane:N`, `workspace:N`, `window:N`).
- Use `--id-format both` only when a UUID must be logged/exported.

## Known WKWebView Gaps (`not_supported`)

- `browser.viewport.set`
- `browser.geolocation.set`
- `browser.offline.set`
- `browser.trace.start|stop`
- `browser.network.route|unroute|requests`
- `browser.screencast.start|stop`
- `browser.input_mouse|input_keyboard|input_touch`

See also:
- [snapshot-refs.md](snapshot-refs.md)
- [authentication.md](authentication.md)
- [session-management.md](session-management.md)
