#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist-wasm}"
WASM_SDK_ID="${WASM_SDK_ID:-}"
PINNED_SDK_ID="$(node -e 'process.stdout.write(require(process.argv[1]).wasi.swiftSDKID)' "$ROOT_DIR/Packaging/PortabilityToolchain.json")"
REQUIRE_WASM_SDK=false
if [ "${1:-}" = "--require-sdk" ]; then REQUIRE_WASM_SDK=true; fi

mkdir -p "$OUTPUT_DIR/browser"
cp "$ROOT_DIR/Packaging/PortabilityToolchain.json" "$OUTPUT_DIR/PortabilityToolchain.json"
cp "$ROOT_DIR"/Examples/WASM/index.html "$ROOT_DIR"/Examples/WASM/app.mjs \
    "$ROOT_DIR"/Examples/WASM/parser-core.mjs "$ROOT_DIR"/Examples/WASM/runtime-worker.mjs \
    "$ROOT_DIR"/Examples/WASM/runtime-client.mjs "$ROOT_DIR"/Examples/WASM/styles.css \
    "$ROOT_DIR"/Examples/WASM/expression-parser.json "$OUTPUT_DIR/browser/"

if [ -z "$WASM_SDK_ID" ]; then WASM_SDK_ID="$PINNED_SDK_ID"; fi
SDK_LIST="$(swift sdk list 2>/dev/null || true)"
if ! printf '%s\n' "$SDK_LIST" | awk '{print $1}' | grep -Fxq "$WASM_SDK_ID"; then WASM_SDK_ID=""; fi
if [ -z "$WASM_SDK_ID" ]; then
    if [ "$REQUIRE_WASM_SDK" = true ]; then
        echo "No Swift WASM SDK is installed. Set WASM_SDK_ID or install a Swift WASM SDK." >&2
        exit 3
    fi
    echo "WASM SDK unavailable; created the portable browser demonstration only."
    echo "Created $OUTPUT_DIR/browser"
    exit 0
fi

SCRATCH="${SCRATCH_PATH:-$ROOT_DIR/.build-wasm}"
"$ROOT_DIR/Scripts/prepare-portable-dependencies.sh" "$SCRATCH"
swift build --package-path "$ROOT_DIR" --scratch-path "$SCRATCH" \
    --swift-sdk "$WASM_SDK_ID" -c release --product grammar-workbench-wasi
BIN_DIR="$(swift build --package-path "$ROOT_DIR" --scratch-path "$SCRATCH" \
    --swift-sdk "$WASM_SDK_ID" -c release --show-bin-path)"
MODULE="$(find "$BIN_DIR" -maxdepth 1 -type f \( -name 'grammar-workbench-wasi' -o -name 'grammar-workbench-wasi.wasm' \) -print -quit)"
if [ -z "$MODULE" ]; then echo "SwiftPM did not produce grammar-workbench-wasi." >&2; exit 2; fi
cp "$MODULE" "$OUTPUT_DIR/grammar-workbench-wasi.wasm"

echo "Created $OUTPUT_DIR/grammar-workbench-wasi.wasm using $WASM_SDK_ID"
echo "Created $OUTPUT_DIR/browser"
