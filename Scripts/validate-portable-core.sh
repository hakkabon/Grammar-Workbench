#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

Scripts/prepare-portable-dependencies.sh
swift build --target GrammarWorkbenchCore
swift test --filter coreFacadeCompilesAndReexportsPortableContracts

echo "Portable core validation passed."
