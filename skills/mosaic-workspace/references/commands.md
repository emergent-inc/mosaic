# mosaic Workspace Command Reference

Use these commands from a mosaic terminal. Most commands infer the caller workspace from `MOSAIC_WORKSPACE_ID`, but explicit flags are safer for automation.

## Context

```bash
mosaic identify --json
mosaic current-workspace --json
mosaic capabilities --json
mosaic ping
```

## Windows and Workspaces

```bash
mosaic list-windows
mosaic current-window
mosaic new-window
mosaic focus-window --window window:2
mosaic close-window --window window:2

mosaic list-workspaces
mosaic list-workspaces --json
mosaic new-workspace --name "task" --cwd "$PWD"
mosaic new-workspace --command "npm run dev"
mosaic new-workspace --layout '{"root":{"type":"terminal"}}'
mosaic current-workspace
mosaic select-workspace --workspace workspace:2
mosaic rename-workspace --workspace workspace:2 -- "new name"
mosaic close-workspace --workspace workspace:2
mosaic reorder-workspace --workspace workspace:4 --before workspace:2
mosaic move-workspace-to-window --workspace workspace:4 --window window:1
```

## Panes and Surfaces

```bash
mosaic list-panes --workspace "$MOSAIC_WORKSPACE_ID"
mosaic list-pane-surfaces --workspace "$MOSAIC_WORKSPACE_ID" --pane pane:1
mosaic list-panels --workspace "$MOSAIC_WORKSPACE_ID"
mosaic tree --workspace "$MOSAIC_WORKSPACE_ID"

mosaic new-split right --workspace "$MOSAIC_WORKSPACE_ID"
mosaic new-split down --workspace "$MOSAIC_WORKSPACE_ID" --surface "$MOSAIC_SURFACE_ID"
mosaic new-pane --workspace "$MOSAIC_WORKSPACE_ID" --type terminal --direction right
mosaic new-pane --workspace "$MOSAIC_WORKSPACE_ID" --type browser --url http://localhost:3000
mosaic new-surface --workspace "$MOSAIC_WORKSPACE_ID" --type terminal --pane pane:1
mosaic new-surface --workspace "$MOSAIC_WORKSPACE_ID" --type browser --pane pane:1 --url http://localhost:3000

mosaic focus-pane --workspace "$MOSAIC_WORKSPACE_ID" --pane pane:2
mosaic focus-panel --workspace "$MOSAIC_WORKSPACE_ID" --panel surface:3
mosaic close-surface --workspace "$MOSAIC_WORKSPACE_ID" --surface surface:3
mosaic move-surface --surface surface:7 --pane pane:2 --focus true
mosaic reorder-surface --surface surface:7 --before surface:3
mosaic move-tab-to-new-workspace --surface surface:7 --title "browser"
```

## Input

```bash
mosaic send "echo hello\n"
mosaic send-key enter
mosaic send --surface "$MOSAIC_SURFACE_ID" "git status\n"
mosaic send-key --surface "$MOSAIC_SURFACE_ID" enter
mosaic read-screen --surface "$MOSAIC_SURFACE_ID"
```

## Sidebar Metadata

```bash
mosaic set-status build "running" --workspace "$MOSAIC_WORKSPACE_ID" --icon hammer --color "#ff9500"
mosaic clear-status build --workspace "$MOSAIC_WORKSPACE_ID"
mosaic list-status --workspace "$MOSAIC_WORKSPACE_ID"
mosaic set-progress 0.5 --workspace "$MOSAIC_WORKSPACE_ID" --label "Building"
mosaic clear-progress --workspace "$MOSAIC_WORKSPACE_ID"
mosaic log --workspace "$MOSAIC_WORKSPACE_ID" --level info -- "Build started"
mosaic list-log --workspace "$MOSAIC_WORKSPACE_ID" --limit 20
mosaic clear-log --workspace "$MOSAIC_WORKSPACE_ID"
mosaic sidebar-state --workspace "$MOSAIC_WORKSPACE_ID" --json
```

## Notifications and Attention

```bash
mosaic notify --title "Done" --body "Task complete"
mosaic list-notifications --json
mosaic clear-notifications
mosaic trigger-flash --workspace "$MOSAIC_WORKSPACE_ID" --surface "$MOSAIC_SURFACE_ID"
mosaic surface-health --workspace "$MOSAIC_WORKSPACE_ID" --json
```

## Config and Docs

```bash
mosaic docs api
mosaic docs browser
mosaic docs settings
mosaic settings path
mosaic settings mosaic-json
mosaic settings shortcuts
mosaic reload-config
```

## Tagged Reloads

```bash
./scripts/reload.sh --tag <short-tag>
MOSAIC_SOCKET_PATH=/tmp/mosaic-debug-<short-tag>.sock mosaic identify --json
```
