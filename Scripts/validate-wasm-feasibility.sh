#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

swift build --product grammar-workbench-wasi
swift test --filter WASMFeasibilityTests
printf '%s\n' '{"schemaVersion":1,"requestID":"wasm-smoke","apiVersion":1,"operation":"capabilities"}' \
    | .build/debug/grammar-workbench-wasi \
    | grep -q '"requestID":"wasm-smoke"'
node Scripts/test-wasm-demo.mjs
Scripts/build-wasm-demo.sh

echo "WASM feasibility and portable demonstration validation passed."
