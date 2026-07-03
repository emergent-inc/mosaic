#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <input-entitlements> <output-entitlements> <bundle-id>" >&2
  exit 2
fi

INPUT="$1"
OUTPUT="$2"
BUNDLE_ID="$3"

if [[ -z "${APPLE_TEAM_ID:-}" ]]; then
  echo "APPLE_TEAM_ID is required to resolve app entitlements" >&2
  exit 1
fi
if [[ ! -f "$INPUT" ]]; then
  echo "input entitlements not found: $INPUT" >&2
  exit 1
fi
if [[ -z "$BUNDLE_ID" ]]; then
  echo "bundle id is required" >&2
  exit 1
fi

APP_ID="${APPLE_TEAM_ID}.${BUNDLE_ID}"
cp "$INPUT" "$OUTPUT"

/usr/libexec/PlistBuddy -c "Delete :com.apple.application-identifier" "$OUTPUT" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $APP_ID" "$OUTPUT"

/usr/libexec/PlistBuddy -c "Delete :com.apple.developer.team-identifier" "$OUTPUT" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $APPLE_TEAM_ID" "$OUTPUT"

/usr/libexec/PlistBuddy -c "Delete :keychain-access-groups" "$OUTPUT" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :keychain-access-groups array" "$OUTPUT"
/usr/libexec/PlistBuddy -c "Add :keychain-access-groups:0 string $APP_ID" "$OUTPUT"
