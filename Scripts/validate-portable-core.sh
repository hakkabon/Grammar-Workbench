#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

node Scripts/measure-workbench-core.mjs --check
swift build --force-resolved-versions --jobs "${SWIFT_BUILD_JOBS:-2}" --target GrammarWorkbenchCore
swift test --force-resolved-versions --jobs "${SWIFT_BUILD_JOBS:-2}" --filter coreModuleCompilesPortableContracts

echo "Portable core validation passed."
