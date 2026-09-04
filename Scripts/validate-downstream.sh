#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH_ROOT="${DOWNSTREAM_SCRATCH_ROOT:-$ROOT_DIR/.build/downstream-consumers}"
SWIFT_BUILD_JOBS="${SWIFT_BUILD_JOBS:-2}"
case "$SWIFT_BUILD_JOBS" in
    ''|*[!0-9]*|0)
        echo "SWIFT_BUILD_JOBS must be a positive integer." >&2
        exit 2
        ;;
esac

run_consumer() {
    local name="$1"
    local package="$ROOT_DIR/Validation/Consumers/$name"
    local output
    output="$(swift run --package-path "$package" --scratch-path "$SCRATCH_ROOT/$name" --jobs "$SWIFT_BUILD_JOBS")"
    case "$name:$output" in
        LibraryConsumer:*library-consumer-ok*) ;;
        CoreConsumer:*core-consumer-ok*) ;;
        LSPConsumer:*lsp-consumer-ok*) ;;
        PluginConsumer:*plugin-consumer-ok*) ;;
        SDKConsumer:*sdk-consumer-ok*) ;;
        *) echo "$name produced unexpected output: $output" >&2; exit 1 ;;
    esac
}

run_consumer LibraryConsumer
run_consumer CoreConsumer
run_consumer LSPConsumer
run_consumer PluginConsumer
run_consumer SDKConsumer
echo "Downstream compatibility validation passed."
