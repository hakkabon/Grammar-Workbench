#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ "$(uname -s)" != "Linux" ]; then
    echo "Linux delivery validation must run on Linux." >&2
    exit 2
fi

cd "$ROOT_DIR"
swift build --product grammar-workbench
swift build --product grammar-workbench-lsp
swift build --product grammar-workbench-service
swift test --filter coreFacadeCompilesAndReexportsPortableContracts
swift test --filter runtimePlatformReportIsStablePortableAndComplete

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/grammar-workbench-linux-validation.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
OUTPUT_DIR="$WORK_DIR/release" Scripts/package-linux.sh
ARCHIVE="$(find "$WORK_DIR/release" -name '*.tar.gz' -type f -print -quit)"
test -n "$ARCHIVE"
tar -xzf "$ARCHIVE" -C "$WORK_DIR"
PACKAGE_DIR="$(find "$WORK_DIR" -maxdepth 1 -type d -name 'Grammar-Workbench-*-linux-*' -print -quit)"
test -x "$PACKAGE_DIR/bin/grammar-workbench"
test -x "$PACKAGE_DIR/bin/grammar-workbench-lsp"
test -x "$PACKAGE_DIR/bin/grammar-workbench-service"
grep -q '"operatingSystem" : "linux"' "$PACKAGE_DIR/platform.json"
Scripts/smoke-release.sh "$PACKAGE_DIR/bin/grammar-workbench"
Scripts/smoke-lsp.sh "$PACKAGE_DIR/bin/grammar-workbench-lsp"
Scripts/smoke-tooling-service.sh "$PACKAGE_DIR/bin/grammar-workbench-service"

echo "Linux delivery validation passed."
