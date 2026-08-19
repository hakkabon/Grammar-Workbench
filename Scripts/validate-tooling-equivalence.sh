#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NATIVE_HOST="${NATIVE_HOST:-$ROOT_DIR/.build/debug/grammar-workbench-wasi}"
WASM_MODULE="${WASM_MODULE:-$ROOT_DIR/dist-wasm/grammar-workbench-wasi.wasm}"
WASI_RUNTIME="${WASI_RUNTIME:-wasmtime}"
REQUIRE_WASM=false
if [ "${1:-}" = "--require-wasm" ]; then REQUIRE_WASM=true
elif [ "$#" -ne 0 ]; then echo "usage: validate-tooling-equivalence.sh [--require-wasm]" >&2; exit 2
fi

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/grammar-workbench-equivalence.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT
REQUESTS="$TMP_ROOT/requests.jsonl"
NATIVE_RESPONSES="$TMP_ROOT/native.jsonl"
WASI_RESPONSES="$TMP_ROOT/wasi.jsonl"
printf '%s\n' "$(cat "$ROOT_DIR/Validation/WASM/capabilities.json")" \
    "$(cat "$ROOT_DIR/Validation/WASM/parse.json")" > "$REQUESTS"

"$NATIVE_HOST" < "$REQUESTS" > "$NATIVE_RESPONSES"
if [ -s "$WASM_MODULE" ] && command -v "$WASI_RUNTIME" >/dev/null 2>&1; then
    "$WASI_RUNTIME" "$WASM_MODULE" < "$REQUESTS" > "$WASI_RESPONSES"
    node "$ROOT_DIR/Scripts/compare-portable-tooling.mjs" "$NATIVE_RESPONSES" "$WASI_RESPONSES"
elif [ "$REQUIRE_WASM" = true ]; then
    echo "A WASM module and the $WASI_RUNTIME runtime are required for equivalence validation." >&2
    exit 3
else
    node "$ROOT_DIR/Scripts/compare-portable-tooling.mjs" "$NATIVE_RESPONSES"
fi
