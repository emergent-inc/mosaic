#!/usr/bin/env bash
# Lint: every Swift file under mosaicTests/ must be wired into
# mosaic.xcodeproj/project.pbxproj.
#
# A test file added to the worktree but not registered as a PBXFileReference +
# PBXSourcesBuildPhase entry in project.pbxproj is silently ignored by Xcode and
# never compiles or runs on CI. Both bot reviews and
# `xcodebuild test -only-testing:mosaicTests/<TestClass>` pass with
# "Executed 0 tests" — so missing wiring is indistinguishable from a passing
# regression test until a real user hits the bug the test was supposed to catch.
#
# Originally surfaced during the https://github.com/emergent-inc/mosaic/issues/4529
# investigation, where SessionIndexJSONLStreamTests.swift on
# https://github.com/emergent-inc/mosaic/pull/4536 looked like a clean two-commit
# red/green test fix but never actually ran on CI.
#
# Usage:
#   ./scripts/lint-pbxproj-test-wiring.sh [--repo-root <path>]
#
# Exit codes:
#   0 — all test files wired correctly (or no test files present)
#   1 — at least one test file is missing pbxproj wiring
#   2 — invocation error (e.g. project.pbxproj not found)

set -euo pipefail

REPO_ROOT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo-root)
      REPO_ROOT="$2"
      shift 2
      ;;
    -h|--help)
      sed -n '1,25p' "$0" | sed 's/^# *//'
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [ -z "$REPO_ROOT" ]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"
fi

PBXPROJ="$REPO_ROOT/mosaic.xcodeproj/project.pbxproj"
TESTS_DIR="$REPO_ROOT/mosaicTests"

if [ ! -f "$PBXPROJ" ]; then
  echo "lint-pbxproj-test-wiring: not found: $PBXPROJ" >&2
  echo "  (run from the mosaic repo root or pass --repo-root)" >&2
  exit 2
fi
if [ ! -d "$TESTS_DIR" ]; then
  echo "lint-pbxproj-test-wiring: not found: $TESTS_DIR" >&2
  exit 2
fi

# Locate the mosaicTests PBXNativeTarget and resolve its Sources build phase
# UUID. We then slice out just that build phase block and look for files inside
# it — which is exactly the set of files Xcode compiles into mosaicTests.
#
# Targeting the mosaicTests Sources phase specifically (instead of the whole
# pbxproj) catches three failure modes:
#   1. File missing entirely (no `<file>.swift in Sources` anywhere).
#   2. File has a PBXFileReference + group child but no PBXBuildFile /
#      Sources phase entry (in the project tree but not a member of any
#      target).
#   3. File is a member of the wrong target (e.g. mosaicUITests or mosaic). Its
#      `<file>.swift in Sources` lines exist in the pbxproj, so a global grep
#      would pass, but they are not inside the mosaicTests Sources block.
# `/* mosaicTests */ = {` appears twice in a typical pbxproj: once for the
# PBXGroup that holds the test files, and once for the PBXNativeTarget. We
# only care about the native-target block. Use awk to capture every
# `/* mosaicTests */ = { ... };` block and keep only the one whose `isa =
# PBXNativeTarget;` line is present.
tests_target_block="$(awk '
  /\/\* mosaicTests \*\/ = \{/ { capture = 1; buf = "" }
  capture { buf = buf $0 "\n" }
  capture && /^[[:space:]]*\};[[:space:]]*$/ {
    if (buf ~ /isa = PBXNativeTarget;/) {
      print buf
      exit
    }
    capture = 0
    buf = ""
  }
' "$PBXPROJ")"

if [ -z "$tests_target_block" ]; then
  echo "lint-pbxproj-test-wiring: could not locate mosaicTests PBXNativeTarget in $PBXPROJ" >&2
  exit 2
fi

# Xcode UUIDs are conventionally 24 uppercase hex chars, but hand-edited
# pbxprojs occasionally use 24-char identifiers that include other uppercase
# letters or digits. Match both.
tests_sources_uuid="$(printf '%s\n' "$tests_target_block" \
  | grep -oE '[A-Z0-9]{24} /\* Sources \*/' \
  | head -n 1 \
  | awk '{print $1}')"

if [ -z "$tests_sources_uuid" ]; then
  echo "lint-pbxproj-test-wiring: mosaicTests target has no Sources build phase reference" >&2
  exit 2
fi

# Slice the PBXSourcesBuildPhase block whose UUID matches the mosaicTests
# target's Sources phase reference. The block begins with the UUID/Sources
# header and ends at the next standalone "};" line.
tests_sources_block="$(awk -v uuid="$tests_sources_uuid" '
  $0 ~ uuid " /\\* Sources \\*/ = \\{" { capture = 1 }
  capture { print }
  capture && /^[[:space:]]*\};[[:space:]]*$/ { exit }
' "$PBXPROJ")"

if [ -z "$tests_sources_block" ]; then
  echo "lint-pbxproj-test-wiring: could not slice mosaicTests Sources build phase (uuid=$tests_sources_uuid)" >&2
  exit 2
fi

missing=()
checked=0

while IFS= read -r -d '' file; do
  base="$(basename "$file")"
  checked=$((checked + 1))
  # Look for the file's entry inside the mosaicTests Sources phase only.
  #
  # Match the full PBX comment `/* <base> in Sources */` as a fixed string
  # (grep -F) so we don't get a false positive when `<base>` is a substring
  # of another wired file. Example: `SearchIndexTests.swift` is a suffix of
  # `SettingsSearchIndexTests.swift`; without these anchors, removing the
  # former from the Sources phase would still match the latter and the lint
  # would pass.
  if ! grep -qF -- "/* $base in Sources */" <<<"$tests_sources_block"; then
    missing+=("$base")
  fi
done < <(find "$TESTS_DIR" -maxdepth 1 -type f -name '*.swift' -print0)

if [ "${#missing[@]}" -eq 0 ]; then
  echo "lint-pbxproj-test-wiring: ok (checked $checked test files)"
  exit 0
fi

echo "lint-pbxproj-test-wiring: ${#missing[@]} test file(s) not a member of the mosaicTests target's Sources build phase (uuid=$tests_sources_uuid) in mosaic.xcodeproj/project.pbxproj"
for entry in "${missing[@]}"; do
  echo "  - $entry"
done
echo ""
echo "Each mosaicTests/<file>.swift must be wired into mosaic.xcodeproj/project.pbxproj"
echo "as a full target member of mosaicTests:"
echo "  1. a PBXBuildFile entry (line ends with '<file>.swift in Sources */ = { ... };')"
echo "  2. a PBXFileReference entry"
echo "  3. an entry in the mosaicTests group children list"
echo "  4. an entry in the mosaicTests target's PBXSourcesBuildPhase files"
echo "     (line ends with '<file>.swift in Sources */,')"
echo ""
echo "This lint slices the mosaicTests Sources phase and looks for entry 4 there."
echo "Files wired only into mosaicUITests, mosaic, or the project tree (without"
echo "mosaicTests target membership) are silently skipped by Xcode and will be"
echo "flagged here."
echo ""
echo "Add via Xcode (drag the file into the mosaicTests target) or hand-edit"
echo "the four blocks (see any wired sibling test as a template)."
exit 1
