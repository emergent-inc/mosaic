#!/usr/bin/env bash
set -euo pipefail

URL="${1:-https://example.com/form}"
SURFACE="${2:-surface:1}"

mosaic browser "$SURFACE" goto "$URL"
mosaic browser "$SURFACE" get url
mosaic browser "$SURFACE" wait --load-state complete --timeout-ms 15000
mosaic browser "$SURFACE" snapshot --interactive

echo "Now run fill/click commands using refs from the snapshot above."
