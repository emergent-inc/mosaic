# Windows and Workspaces

Window/workspace lifecycle and ordering operations.

## Inspect

```bash
mosaic list-windows
mosaic current-window
mosaic list-workspaces
mosaic current-workspace
```

## Create/Focus/Close

```bash
mosaic new-window
mosaic focus-window --window window:2
mosaic close-window --window window:2

mosaic new-workspace
mosaic select-workspace --workspace workspace:4
mosaic close-workspace --workspace workspace:4
```

## Reorder and Move

```bash
mosaic reorder-workspace --workspace workspace:4 --before workspace:2
mosaic move-workspace-to-window --workspace workspace:4 --window window:1
```
