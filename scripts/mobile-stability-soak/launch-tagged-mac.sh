#!/usr/bin/env bash
set -euo pipefail

tag="${MOSAIC_TAG:-swmob}"
repo="${MOSAIC_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
app="${MOSAIC_SWAPP:-$HOME/Library/Developer/Xcode/DerivedData/mosaic-${tag}/Build/Products/Debug/Mosaic DEV ${tag}.app}"
port="${MOSAIC_PORT:-9300}"
port_range="${MOSAIC_PORT_RANGE:-10}"
port_end="${MOSAIC_PORT_END:-$((port + port_range - 1))}"
dev_origin="${MOSAIC_DEV_ORIGIN:-http://localhost:${port}}"
bin="$app/Contents/MacOS/Mosaic DEV"
tag_bundle_id="$(printf '%s' "$tag" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/./g; s/^\.+//; s/\.+$//; s/\.+/./g')"
if [[ -z "$tag_bundle_id" ]]; then
  tag_bundle_id="agent"
fi

if [[ ! -x "$bin" ]]; then
  echo "missing tagged app binary: $bin" >&2
  exit 1
fi

exec env \
  MOSAIC_BUNDLE_ID="mosaic.com.emergent.app.debug.${tag_bundle_id}" \
  MOSAIC_SOCKET_ENABLE=1 \
  MOSAIC_SOCKET_MODE=allowAll \
  MOSAIC_SOCKET_PATH="/tmp/mosaic-debug-${tag}.sock" \
  MOSAICD_UNIX_PATH="$HOME/Library/Application Support/mosaic/mosaicd-dev-${tag}.sock" \
  MOSAIC_DEBUG_LOG="/tmp/mosaic-debug-${tag}.log" \
  MOSAIC_API_BASE_URL="$dev_origin" \
  MOSAIC_AUTH_WWW_ORIGIN="$dev_origin" \
  MOSAIC_VM_API_BASE_URL="$dev_origin" \
  MOSAIC_PORT="$port" \
  MOSAIC_PORT_RANGE="$port_range" \
  MOSAIC_PORT_END="$port_end" \
  PORT="$port" \
  MOSAIC_BUNDLED_CLI_PATH="$app/Contents/Resources/bin/mosaic" \
  MOSAIC_SHELL_INTEGRATION_DIR="$app/Contents/Resources/shell-integration" \
  MOSAIC_REMOTE_DAEMON_ALLOW_LOCAL_BUILD=1 \
  MOSAICTERM_REPO_ROOT="$repo" \
  "$bin"
