#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CRATE_DIR="${ROOT}/Native/CommandPaletteNucleoFFI"
DERIVED_DATA="${MOSAIC_NUCLEO_FFI_DERIVED_DATA:-/tmp/mosaic-nucleo-ffi-unit}"
LOG_PATH="${MOSAIC_NUCLEO_FFI_LOG:-/tmp/mosaic-nucleo-ffi-tests.log}"

cargo build --manifest-path "${CRATE_DIR}/Cargo.toml" --release

LIB_PATH="${CRATE_DIR}/target/release/libmosaic_command_palette_nucleo_ffi.dylib"
if [ ! -f "${LIB_PATH}" ]; then
  echo "error: expected nucleo FFI library at ${LIB_PATH}" >&2
  exit 1
fi

if [ "${MOSAIC_NUCLEO_FFI_CLEAN:-0}" = "1" ]; then
  rm -rf "${DERIVED_DATA}"
fi
NSUnbufferedIO=YES MOSAIC_NUCLEO_FFI_LIB="${LIB_PATH}" \
  xcodebuild \
    -project "${ROOT}/mosaic.xcodeproj" \
    -scheme mosaic-unit \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "${DERIVED_DATA}" \
    -only-testing:mosaicTests/CommandPaletteNucleoFFITests \
    test | tee "${LOG_PATH}"

if ! grep 'BENCH cmd+p nucleo-ffi' "${LOG_PATH}"; then
  echo "error: CommandPaletteNucleoFFITests did not emit benchmark output" >&2
  exit 1
fi
