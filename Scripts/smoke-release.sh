#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "usage: smoke-release.sh CLI_PATH" >&2
    exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLI_PATH="$1"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/grammar-workbench-smoke.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

test -x "$CLI_PATH"
for GRAMMAR in "$ROOT_DIR"/Examples/Corpus/*.grammar; do
    "$CLI_PATH" validate "$GRAMMAR" >/dev/null
done

"$CLI_PATH" compare "$ROOT_DIR/Examples/Corpus/MiniLanguage.grammar" "$WORK_DIR/comparison.json"
"$CLI_PATH" export-artifact "$ROOT_DIR/Examples/Corpus/JSONSubset.grammar" "$WORK_DIR/artifact.json"
"$CLI_PATH" generate swift "$ROOT_DIR/Examples/Corpus/MiniLanguage.grammar" "$WORK_DIR/GeneratedParser.swift" "LALR(1)" typeName=SmokeParser
"$CLI_PATH" generate bnf "$ROOT_DIR/Examples/Corpus/JSONSubset.grammar" "$WORK_DIR/JSONSubset.bnf"

test -s "$WORK_DIR/comparison.json"
test -s "$WORK_DIR/artifact.json"
test -s "$WORK_DIR/GeneratedParser.swift"
test -s "$WORK_DIR/JSONSubset.bnf"
swiftc -parse "$WORK_DIR/GeneratedParser.swift"

echo "Release smoke tests passed."
