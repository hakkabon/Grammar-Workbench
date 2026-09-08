#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

node Scripts/measure-workbench-core.mjs --check
swift build --force-resolved-versions --target GrammarWorkbenchCore
swift test --force-resolved-versions --filter coreFacadeCompilesAndReexportsPortableContracts

echo "Portable core validation passed."
