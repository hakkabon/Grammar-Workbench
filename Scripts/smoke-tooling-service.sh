#!/bin/bash
set -euo pipefail

SERVICE_PATH="${1:?usage: smoke-tooling-service.sh SERVICE_PATH}"
REQUEST='{"apiVersion":1,"operation":"capabilities","requestID":"smoke-capabilities","schemaVersion":1}'
OUTPUT="$(printf '%s\n' "$REQUEST" | "$SERVICE_PATH")"

for REQUIRED in '"requestID":"smoke-capabilities"' '"status":"success"' '"json-lines"' '"sessionOpen"'; do
    case "$OUTPUT" in
        *"$REQUIRED"*) ;;
        *) echo "Tooling service returned an unexpected capability response: $OUTPUT" >&2; exit 1 ;;
    esac
done

echo "Stateful tooling service smoke test passed."
