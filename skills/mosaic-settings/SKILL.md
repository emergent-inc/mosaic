---
name: mosaic-settings
description: "View and edit mosaic settings in ~/.config/mosaic/mosaic.json. Use when the user wants to change mosaic preferences (appearance, sidebar, notifications, automation, browser, shortcuts), set a value by JSON path, validate the file, open it in an editor, or look up which keys mosaic recognizes. Triggers on '/mosaic-settings', 'change mosaic setting', 'set <something> in mosaic', 'mosaic config', 'mosaic.json', or 'rebind a mosaic shortcut'."
---

# mosaic-settings

mosaic reads user settings from `~/.config/mosaic/mosaic.json` (JSONC). The app installs a file watcher; saving the file applies changes immediately, no restart needed. Legacy `~/.config/mosaic/settings.json` is read only as a fallback for keys not present in `mosaic.json`.

Schema: `https://raw.githubusercontent.com/emergent-inc/mosaic/main/web/data/mosaic.schema.json`. The authoritative path list lives in `Sources/MosaicSettingsJSONPathSupport.swift` in the mosaic checkout, and the installed skill includes a generated copy in `references/all-keys.md`. Top-level sections are `app`, `terminal`, `notifications`, `sidebar`, `sidebarAppearance`, `workspaceColors`, `automation`, `browser`, and `shortcuts`. Non-settings sections (`actions`, `ui`, `commands`, `vault`, `rightSidebar`) coexist in the same file.

## Helper script

Use the bundled helper for every read/write. It strips JSONC comments, writes atomically, and validates keys against the schema.

```bash
# From a mosaic checkout
skills/mosaic-settings/scripts/mosaic-settings <subcommand>

# From an installed Codex skill
~/.codex/skills/mosaic-settings/scripts/mosaic-settings <subcommand>
```

For brevity in the rest of this doc, assume the script is on `$PATH` as `mosaic-settings`. To make it so for a session from a checkout: `export PATH="$PWD/skills/mosaic-settings/scripts:$PATH"`.

Subcommands:

| Command | What it does |
|---|---|
| `mosaic-settings path` | Print the config path. |
| `mosaic-settings dump` | Print the raw file (preserves comments). |
| `mosaic-settings dump --no-comments` | Print the parsed JSON. |
| `mosaic-settings get <a.b.c>` | Print value at dotted JSON path. |
| `mosaic-settings set <a.b.c> <value>` | Set value. `<value>` is parsed as JSON (`true`, `42`, `"text"`, `[…]`, `{…}`); plain strings without quotes are stored as strings. |
| `mosaic-settings unset <a.b.c>` | Delete key, reverting to the in-app default. |
| `mosaic-settings list-supported` | List every settings JSON path the app recognizes. |
| `mosaic-settings validate` | Parse the file and flag any unknown settings keys. |
| `mosaic-settings open` | Open `mosaic.json` in `$EDITOR`, VS Code, Cursor, or TextEdit. |

`--file <path>` overrides the target file (useful for `--file ~/.config/mosaic/settings.json` when the user keeps things in the legacy file).

## Workflow

1. Confirm the change. If the user named a setting in plain English (e.g. "make the sidebar tint match the terminal background"), look it up first.
   ```bash
   mosaic-settings list-supported | rg -i 'sidebar.*terminal|terminal.*sidebar'
   ```
2. Set the value. JSON literals (`true`, `false`, numbers, arrays, objects) must be valid JSON. Plain words are stored as strings.
   ```bash
   mosaic-settings set sidebarAppearance.matchTerminalBackground true
   mosaic-settings set app.appearance dark
   mosaic-settings set shortcuts.bindings.toggleSidebar cmd+b
   mosaic-settings set shortcuts.bindings.newTab '["ctrl+b","c"]'
   mosaic-settings set browser.hostsToOpenInEmbeddedBrowser '["localhost","*.internal.example"]'
   ```
3. Verify by reading back and validating.
   ```bash
   mosaic-settings get sidebarAppearance.matchTerminalBackground
   mosaic-settings validate
   ```
4. Tell the user it auto-reloaded. No app restart. If they want to revert, run `mosaic-settings unset <key>`.

## Quick reference

- Appearance: `app.appearance` = `"system" | "light" | "dark"`, `app.appIcon`, `app.menuBarOnly`, `app.minimalMode`.
- Sidebar tint: `sidebarAppearance.matchTerminalBackground`, `sidebarAppearance.tintColor`, `sidebarAppearance.tintOpacity` (0..1).
- Sidebar details: `sidebar.hideAllDetails`, `sidebar.showBranchDirectory`, `sidebar.showPullRequests`, `sidebar.showPorts`, `sidebar.showLog`.
- Notifications: `notifications.dockBadge`, `notifications.sound` (enum incl. `"none"`, `"custom_file"`), `notifications.customSoundFilePath`, `notifications.hooks` (array).
- Browser: `browser.defaultSearchEngine`, `browser.theme`, `browser.openTerminalLinksInMosaicBrowser`, `browser.hostsToOpenInEmbeddedBrowser`.
- Automation: `automation.socketControlMode` (`off | mosaicOnly | automation | password | allowAll`), `automation.portBase`, `automation.portRange`.
- Shortcuts: `shortcuts.bindings.<actionId>` = `"cmd+b"`, `["ctrl+b","c"]`, `null`, or `""` to unbind. See `references/shortcut-actions.md`.

For the full list of settings, defaults, and descriptions, run `mosaic-settings list-supported` or read [references/all-keys.md](references/all-keys.md).

## Rules

- Only edit `mosaic.json`. Never edit `settings.json` unless the user explicitly asks; it is legacy and only read when the key is absent from `mosaic.json`.
- Never tell the user to restart mosaic to apply a change. The file watcher reloads on save.
- Always validate after a bulk edit: `mosaic-settings validate`. Unknown keys mean the user pasted a key the app does not consume.
- Do not blindly overwrite top-level sections (`actions`, `ui`, `commands`, `vault`, `rightSidebar`). They live in the same file and contain non-settings config the user has hand-tuned.
- Shortcut action ids must match the schema enum. Look them up in [references/shortcut-actions.md](references/shortcut-actions.md) before binding.
- Color values must be `#RRGGBB`. Opacities are `0..1`.
- For settings the user expressed in app-level language (e.g. "Settings > Notifications > Dock badge"), translate to the matching JSON path first; the docs page at `web/app/[locale]/docs/configuration/page.tsx` mirrors the schema 1:1.
