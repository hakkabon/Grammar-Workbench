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
"$CLI_PATH" validate "$ROOT_DIR/Examples/Expression.ebnf" >/dev/null
"$CLI_PATH" lower-ebnf "$ROOT_DIR/Examples/Expression.ebnf" "$WORK_DIR/Expression.bnf"
"$CLI_PATH" diff "$ROOT_DIR/Examples/Expression.grammar" "$ROOT_DIR/Examples/Corpus/JSONSubset.grammar" "$WORK_DIR/diff.json"
"$CLI_PATH" generate semantic-model-json "$ROOT_DIR/Examples/Expression.grammar" "$WORK_DIR/Expression.semantic.json"
"$CLI_PATH" generate semantic-swift "$ROOT_DIR/Examples/Expression.grammar" "$WORK_DIR/ExpressionSemantics.swift" typeName=ExpressionSemantics
"$CLI_PATH" parse "$ROOT_DIR/Examples/Expression.grammar" "left + right" "$WORK_DIR/parse.json"
"$CLI_PATH" generalized-parse "$ROOT_DIR/Examples/Expression.grammar" "left + middle + right" "$WORK_DIR/generalized.json" --include-resolved --breadth-first --maximum-trees=8
"$CLI_PATH" platform-parse "$ROOT_DIR/Examples/Corpus/ExpectedConflict.grammar" "if condition then if nested then left else right" "$WORK_DIR/platform.json" --ambiguity=firstStable
"$CLI_PATH" grammar-analyze "$ROOT_DIR/Examples/TransformationCleanup.grammar" "$WORK_DIR/analysis.json"
"$CLI_PATH" grammar-transform unreachable "$ROOT_DIR/Examples/TransformationCleanup.grammar" "$WORK_DIR/cleaned.grammar"
"$CLI_PATH" validate "$WORK_DIR/cleaned.grammar" >/dev/null
"$CLI_PATH" project-check "$ROOT_DIR/Examples/ExpressionProject.json"
"$CLI_PATH" source-project-check "$ROOT_DIR/Examples/SourceProject/.grammar-workbench-source.json"
"$CLI_PATH" source-project-export "$ROOT_DIR/Examples/SourceProject/.grammar-workbench-source.json" "$WORK_DIR/source-project.json"
"$CLI_PATH" project-generate "$ROOT_DIR/Examples/ExpressionProject.json" "$WORK_DIR/project-output"
"$CLI_PATH" kit-validate "$ROOT_DIR/Examples/TinySemanticLanguageKit.json"
"$CLI_PATH" kit-project "$ROOT_DIR/Examples/TinySemanticLanguageKit.json" "$WORK_DIR/kit-project.json"
"$CLI_PATH" graph-layout "$ROOT_DIR/Examples/GraphVisualization.json" "$WORK_DIR/graph-layout.json"
"$CLI_PATH" graph-layout "$ROOT_DIR/Examples/GraphVisualization.json" "$WORK_DIR/graph-layout.svg"
"$CLI_PATH" portable-import "$ROOT_DIR/Examples/PortableArithmetic.bnf" "$WORK_DIR/portable-grammar.json" --notation=bnfProfile --start=expression
"$CLI_PATH" portable-render "$WORK_DIR/portable-grammar.json" "$WORK_DIR/portable-grammar.bnf" --format=bnfProfile --verify
"$CLI_PATH" bootstrap-bundle "$WORK_DIR/bootstrap-bundle.json"
"$CLI_PATH" research-validate "$ROOT_DIR/Examples/ResearchValidationProgramme.json" "$WORK_DIR/research-baseline.json"
"$CLI_PATH" research-validate "$ROOT_DIR/Examples/ResearchValidationProgramme.json" "$WORK_DIR/research-candidate.json"
"$CLI_PATH" research-compare "$WORK_DIR/research-baseline.json" "$WORK_DIR/research-candidate.json" "$WORK_DIR/research-comparison.json"
"$CLI_PATH" research-preview list > "$WORK_DIR/research-preview-list.txt"
"$CLI_PATH" research-preview precedence-hidden-ambiguity "$WORK_DIR/research-preview.json"

test -s "$WORK_DIR/comparison.json"
test -s "$WORK_DIR/artifact.json"
test -s "$WORK_DIR/GeneratedParser.swift"
test -s "$WORK_DIR/JSONSubset.bnf"
test -s "$WORK_DIR/Expression.semantic.json"
test -s "$WORK_DIR/ExpressionSemantics.swift"
test -s "$WORK_DIR/parse.json"
test -s "$WORK_DIR/generalized.json"
test -s "$WORK_DIR/platform.json"
test -s "$WORK_DIR/analysis.json"
test -s "$WORK_DIR/cleaned.grammar"
test -s "$WORK_DIR/project-output/Generated/Grammar.semantic.json"
test -s "$WORK_DIR/source-project.json"
test -s "$WORK_DIR/kit-project.json"
test -s "$WORK_DIR/graph-layout.json"
test -s "$WORK_DIR/graph-layout.svg"
test -s "$WORK_DIR/portable-grammar.json"
test -s "$WORK_DIR/portable-grammar.bnf"
test -s "$WORK_DIR/bootstrap-bundle.json"
test -s "$WORK_DIR/research-baseline.json"
test -s "$WORK_DIR/research-candidate.json"
test -s "$WORK_DIR/research-comparison.json"
test -s "$WORK_DIR/research-preview-list.txt"
test -s "$WORK_DIR/research-preview.json"
swiftc -parse "$WORK_DIR/GeneratedParser.swift"
swiftc -parse "$WORK_DIR/ExpressionSemantics.swift"

echo "Release smoke tests passed."
