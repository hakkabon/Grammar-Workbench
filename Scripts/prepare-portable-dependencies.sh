#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH_PATH="${1:-$ROOT_DIR/.build}"
GRAMMAR_REVISION="940fdb4f857391e7cdecbb016adabd33db2121c8"
PATCH="$ROOT_DIR/Patches/Grammar-940fdb4-portable-oslog.patch"

swift package --package-path "$ROOT_DIR" --scratch-path "$SCRATCH_PATH" resolve

CHECKOUT="$SCRATCH_PATH/checkouts/Grammar"
if [ ! -d "$CHECKOUT/.git" ]; then
    echo "Grammar checkout was not created at $CHECKOUT." >&2
    exit 2
fi
if [ "$(git -C "$CHECKOUT" rev-parse HEAD)" != "$GRAMMAR_REVISION" ]; then
    echo "Portable Grammar patch only supports revision $GRAMMAR_REVISION." >&2
    exit 2
fi

if git -C "$CHECKOUT" apply --reverse --check "$PATCH" >/dev/null 2>&1; then
    echo "Portable Grammar OSLog compatibility patch is already applied."
elif git -C "$CHECKOUT" apply --check "$PATCH"; then
    git -C "$CHECKOUT" apply "$PATCH"
    echo "Applied portable Grammar OSLog compatibility patch."
else
    echo "Portable Grammar OSLog compatibility patch no longer applies cleanly." >&2
    exit 2
fi
