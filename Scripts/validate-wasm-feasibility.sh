#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

Scripts/prepare-portable-dependencies.sh
swift build --product grammar-workbench-wasi
swift test --filter WASMFeasibilityTests
Scripts/validate-tooling-equivalence.sh
node Scripts/test-wasm-demo.mjs
Scripts/build-wasm-demo.sh

echo "WASM feasibility and portable demonstration validation passed."
