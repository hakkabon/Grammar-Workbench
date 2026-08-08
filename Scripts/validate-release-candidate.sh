#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE_RELEASE=0
if [ "${1:-}" = "--package" ]; then
    PACKAGE_RELEASE=1
elif [ "$#" -ne 0 ]; then
    echo "usage: validate-release-candidate.sh [--package]" >&2
    exit 2
fi

plutil -lint "$ROOT_DIR/Packaging/Info.plist" \
    "$ROOT_DIR/Packaging/GrammarWorkbench.entitlements"

swift test --package-path "$ROOT_DIR"
swift build --package-path "$ROOT_DIR" -c release --product grammar-workbench
swift build --package-path "$ROOT_DIR" -c release --product grammar-workbench-lsp
BIN_DIR="$(swift build --package-path "$ROOT_DIR" -c release --show-bin-path)"
"$ROOT_DIR/Scripts/smoke-release.sh" "$BIN_DIR/grammar-workbench"
"$ROOT_DIR/Scripts/smoke-lsp.sh" "$BIN_DIR/grammar-workbench-lsp"
if command -v node >/dev/null 2>&1; then
    (cd "$ROOT_DIR" && node Scripts/m4-client-test.js)
else
    echo "node not found; skipping the dependency-free VS Code client protocol test."
fi
"$ROOT_DIR/Scripts/validate-downstream.sh"

if [ "$PACKAGE_RELEASE" -eq 1 ]; then
    RC_OUTPUT="${OUTPUT_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/grammar-workbench-rc.XXXXXX")}"
    OUTPUT_DIR="$RC_OUTPUT" "$ROOT_DIR/Scripts/package-release.sh"
    test -s "$RC_OUTPUT/SHA256SUMS"
    echo "Release-candidate artifacts: $RC_OUTPUT"
fi

echo "Release-candidate validation passed."
