#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${MOSAIC_TAG:-}" ]]; then
  cat >&2 <<'EOF'
MOSAIC_TAG is required.

Usage:
  MOSAIC_TAG=<tag> scripts/mosaic-debug-cli.sh <mosaic-command> [args...]

Example:
  MOSAIC_TAG=codext scripts/mosaic-debug-cli.sh list-workspaces
EOF
  exit 2
fi

if [[ ! "$MOSAIC_TAG" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Invalid MOSAIC_TAG: $MOSAIC_TAG" >&2
  exit 2
fi

if [[ $# -eq 0 ]]; then
  echo "Usage: MOSAIC_TAG=$MOSAIC_TAG scripts/mosaic-debug-cli.sh <mosaic-command> [args...]" >&2
  exit 2
fi

sanitize_bundle() {
  local raw="$1"
  local cleaned
  cleaned="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/./g; s/^\.+//; s/\.+$//; s/\.+/./g')"
  if [[ -z "$cleaned" ]]; then
    cleaned="agent"
  fi
  printf '%s\n' "$cleaned"
}

sanitize_path() {
  local raw="$1"
  local cleaned
  cleaned="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
  if [[ -z "$cleaned" ]]; then
    cleaned="agent"
  fi
  printf '%s\n' "$cleaned"
}

tag_slug="$(sanitize_path "$MOSAIC_TAG")"
tag_bundle_id="$(sanitize_bundle "$MOSAIC_TAG")"

socket_path="/tmp/mosaic-debug-${tag_slug}.sock"
if [[ ! -S "$socket_path" ]]; then
  cat >&2 <<EOF
Tagged mosaic socket not found:
  $socket_path

Launch the tagged app first:
  ./scripts/reload.sh --tag $MOSAIC_TAG --launch
EOF
  exit 1
fi

cli_path="${HOME}/Library/Developer/Xcode/DerivedData/mosaic-${tag_slug}/Build/Products/Debug/Mosaic DEV ${tag_slug}.app/Contents/Resources/bin/mosaic"
if [[ ! -x "$cli_path" ]]; then
  cat >&2 <<EOF
Tagged mosaic CLI not found:
  $cli_path

Build the tagged app first:
  ./scripts/reload.sh --tag $MOSAIC_TAG
EOF
  exit 1
fi

unset MOSAIC_SOCKET
unset MOSAIC_SOCKET_PASSWORD
unset MOSAIC_WORKSPACE_ID
unset MOSAIC_SURFACE_ID
unset MOSAIC_TAB_ID
unset MOSAIC_PANEL_ID
unset MOSAICD_UNIX_PATH
unset MOSAIC_DEBUG_LOG
export MOSAIC_SOCKET_PATH="$socket_path"
export MOSAIC_TAG="$tag_slug"
export MOSAIC_BUNDLE_ID="mosaic.com.emergent.app.debug.${tag_bundle_id}"
export MOSAIC_BUNDLED_CLI_PATH="$cli_path"
exec "$cli_path" "$@"
