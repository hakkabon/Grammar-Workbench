#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH_ROOT="${DOWNSTREAM_SCRATCH_ROOT:-$ROOT_DIR/.build/downstream-consumers}"

run_consumer() {
    local name="$1"
    local package="$ROOT_DIR/Validation/Consumers/$name"
    local output
    output="$(swift run --package-path "$package" --scratch-path "$SCRATCH_ROOT/$name")"
    case "$name:$output" in
        LibraryConsumer:*library-consumer-ok*) ;;
        PluginConsumer:*plugin-consumer-ok*) ;;
        *) echo "$name produced unexpected output: $output" >&2; exit 1 ;;
    esac
}

run_consumer LibraryConsumer
run_consumer PluginConsumer
echo "Downstream compatibility validation passed."
