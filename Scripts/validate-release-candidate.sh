#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE_RELEASE=0
SWIFT_BUILD_JOBS="${SWIFT_BUILD_JOBS:-2}"
case "$SWIFT_BUILD_JOBS" in
    ''|*[!0-9]*|0)
        echo "SWIFT_BUILD_JOBS must be a positive integer." >&2
        exit 2
        ;;
esac
export SWIFT_BUILD_JOBS

if [ "${1:-}" = "--package" ]; then
    PACKAGE_RELEASE=1
elif [ "$#" -ne 0 ]; then
    echo "usage: validate-release-candidate.sh [--package]" >&2
    exit 2
fi

plutil -lint "$ROOT_DIR/Packaging/Info.plist" \
    "$ROOT_DIR/Packaging/GrammarWorkbench.entitlements"
node -e 'const m=require(process.argv[1]); if (m.schemaVersion !== 1 || !m.wasi.swiftSDKID || !m.wasi.swiftSDKBundleSHA256) process.exit(1)' \
    "$ROOT_DIR/Packaging/PortabilityToolchain.json"
node "$ROOT_DIR/Scripts/validate-ecosystem-contract.mjs"

swift test --package-path "$ROOT_DIR" --jobs "$SWIFT_BUILD_JOBS"
swift build --package-path "$ROOT_DIR" --jobs "$SWIFT_BUILD_JOBS" -c release --product grammar-workbench
swift build --package-path "$ROOT_DIR" --jobs "$SWIFT_BUILD_JOBS" -c release --product grammar-workbench-lsp
swift build --package-path "$ROOT_DIR" --jobs "$SWIFT_BUILD_JOBS" -c release --product grammar-workbench-service
BIN_DIR="$(swift build --package-path "$ROOT_DIR" --jobs "$SWIFT_BUILD_JOBS" -c release --show-bin-path)"
node "$ROOT_DIR/Scripts/validate-ecosystem-contract.mjs" --cli "$BIN_DIR/grammar-workbench"
"$ROOT_DIR/Scripts/smoke-release.sh" "$BIN_DIR/grammar-workbench"
"$ROOT_DIR/Scripts/smoke-lsp.sh" "$BIN_DIR/grammar-workbench-lsp"
"$ROOT_DIR/Scripts/smoke-tooling-service.sh" "$BIN_DIR/grammar-workbench-service"
if command -v node >/dev/null 2>&1; then
    (cd "$ROOT_DIR" && node Scripts/m4-client-test.js)
    (cd "$ROOT_DIR" && node Scripts/test-wasm-demo.mjs)
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
