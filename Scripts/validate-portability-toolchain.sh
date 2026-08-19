#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT_DIR/Packaging/PortabilityToolchain.json"
REQUIRE_WASM=false
if [ "${1:-}" = "--require-wasm" ]; then REQUIRE_WASM=true
elif [ "$#" -ne 0 ]; then echo "usage: validate-portability-toolchain.sh [--require-wasm]" >&2; exit 2
fi

read_manifest() {
    node -e 'const m=require(process.argv[1]); let v=m; for (const p of process.argv[2].split(".")) v=v[p]; process.stdout.write(String(v))' "$MANIFEST" "$1"
}

EXPECTED_SWIFT="$(read_manifest requiredSwiftVersion)"
EXPECTED_NODE="$(read_manifest nodeMajorVersion)"
EXPECTED_SDK="$(read_manifest wasi.swiftSDKID)"
SWIFT_VERSION="$(swift --version | sed -n '1s/.*Swift version \([0-9][0-9.]*\).*/\1/p')"
NODE_VERSION="$(node --version | sed 's/^v//' | cut -d. -f1)"

case "$SWIFT_VERSION" in
    "$EXPECTED_SWIFT"|"$EXPECTED_SWIFT".*) ;;
    *) echo "Expected Swift $EXPECTED_SWIFT from $MANIFEST, found ${SWIFT_VERSION:-unknown}." >&2; exit 1 ;;
esac
test "$NODE_VERSION" = "$EXPECTED_NODE" || {
    echo "Expected Node major $EXPECTED_NODE from $MANIFEST, found ${NODE_VERSION:-unknown}." >&2; exit 1;
}

SDK_LIST="$(swift sdk list 2>/dev/null || true)"
if ! printf '%s\n' "$SDK_LIST" | awk '{print $1}' | grep -Fxq "$EXPECTED_SDK"; then
    if [ "$REQUIRE_WASM" = true ]; then
        echo "Required Swift SDK $EXPECTED_SDK is not installed." >&2; exit 3
    fi
    echo "Host toolchain matches; optional Swift SDK $EXPECTED_SDK is not installed."
    exit 0
fi
echo "Pinned host and WASI toolchains are installed."
