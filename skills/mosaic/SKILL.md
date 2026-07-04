---
name: mosaic
description: End-user control of mosaic topology and routing (windows, workspaces, panes/surfaces, focus, moves, reorder, identify, trigger flash). Use when automation needs deterministic placement and navigation in a multi-pane mosaic layout.
---

# mosaic Core Control

Use this skill to control non-browser mosaic topology and routing.

## Core Concepts

- Window: top-level macOS mosaic window.
- Workspace: tab-like group within a window.
- Pane: split container in a workspace.
- Surface: a tab within a pane (terminal or browser panel).

## Fast Start

```bash
# identify current caller context
mosaic identify --json

# list topology
mosaic list-windows
mosaic list-workspaces
mosaic list-panes
mosaic list-pane-surfaces --pane pane:1

# create/focus/move
mosaic new-workspace
mosaic new-split right --panel pane:1
mosaic move-surface --surface surface:7 --pane pane:2 --focus true
mosaic split-off --surface surface:7 right
mosaic reorder-surface --surface surface:7 --before surface:3

# attention cue
mosaic trigger-flash --surface surface:7
```

## Settings and Docs

Use `mosaic docs settings` before changing mosaic-owned settings. It prints the docs URL, schema URL, raw GitHub resources, mosaic.json paths, and reload command.

```bash
mosaic docs settings
mosaic settings path
```

mosaic-owned settings live in `~/.config/mosaic/mosaic.json`. Legacy `~/.config/mosaic/settings.json` and `~/Library/Application Support/mosaic.com.emergent.app/settings.json` files are read only as fallback for missing keys. Before editing, copy any existing `mosaic.json` file to a timestamped `.bak` next to it so the user can revert. Edit the user file, then reload:

```bash
mosaic reload-config
```

`mosaic reload-config` reloads BOTH `mosaic.json` and Ghostty config (`~/.config/ghostty/config`) and refreshes terminals in place. No app restart needed.

Use mosaic settings for app behavior, sidebar, notifications, browser behavior, automation, workspace colors, and mosaic-owned shortcuts. Terminal rendering settings such as font, cursor style, theme, scrollback, background transparency (`background-opacity`), and blur (`background-blur`) belong in Ghostty config at `~/.config/ghostty/config`.

Open the UI when useful:

```bash
mosaic settings
mosaic settings mosaic-json
mosaic settings shortcuts
```

## Handle Model

- Default output uses short refs: `window:N`, `workspace:N`, `pane:N`, `surface:N`.
- UUIDs are still accepted as inputs.
- Request UUID output only when needed: `--id-format uuids|both`.

## Deep-Dive References

| Reference | When to Use |
|-----------|-------------|
| [references/handles-and-identify.md](references/handles-and-identify.md) | Handle syntax, self-identify, caller targeting |
| [references/windows-workspaces.md](references/windows-workspaces.md) | Window/workspace lifecycle and reorder/move |
| [references/panes-surfaces.md](references/panes-surfaces.md) | Splits, surfaces, move/reorder, focus routing |
| [references/trigger-flash-and-health.md](references/trigger-flash-and-health.md) | Flash cue and surface health checks |
| [../mosaic-workspace/SKILL.md](../mosaic-workspace/SKILL.md) | Current caller workspace rules and non-disruptive automation |
| [../mosaic-settings/SKILL.md](../mosaic-settings/SKILL.md) | Safe mosaic.json settings edits and validation |
| [../mosaic-browser/SKILL.md](../mosaic-browser/SKILL.md) | Browser automation on surface-backed webviews |
| [../mosaic-markdown/SKILL.md](../mosaic-markdown/SKILL.md) | Markdown viewer panel with live file watching |
