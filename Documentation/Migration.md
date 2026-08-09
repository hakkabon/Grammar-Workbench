# Compatibility and migration

## Project documents

Schema-1 projects remain readable. They default to workbench grammar notation and an empty test suite where those fields were absent. New exports use schema 2.

## Artifact interchange

Schema-1 artifact envelopes remain readable and normalize to schema 2. Consumers should validate both envelope and public API versions and should not persist state or production identifiers across grammar edits.

## Parse results

Older parse-result JSON without `syntaxTree` remains decodable. Consumers should continue accepting the rendered `tree` field while adopting structured syntax nodes.

## Generalized parser engineering

`grammar-workbench generalized-parse` is the supported spelling of the generalized parser command. `research-parse` remains as a compatibility alias. Existing `parseGeneralized` calls remain source-compatible; results now also expose a structured `forest`, stable alternative IDs, exact `reachedLimits`, rejection `syntaxDiagnostics`, and expanded action metrics. Use `parseGeneralizedCancellable` in task-based integrations that need cooperative cancellation.

## Generated parsers

Generated parsers are dependency-free. Regenerate them when upgrading Grammar Workbench so table behavior, recovery, and semantic evaluation remain aligned with the selected release.

## Semantic actions

Existing `GrammarSemanticReducer` implementations remain supported. Applications may adopt `GrammarSemanticActions` incrementally; its production IDs are the same identities already supplied to `reduce(production:children:node:)`. Validate an action set against `GrammarSemanticModel` after grammar changes. The `semantic-swift` generator creates an editable starter and never modifies application sources in place.

## EBNF lowering

Lowering snapshots now include `productionOrigins`. Decoding older snapshots defaults this property to an empty array. Consumers that navigate from parser production IDs may use the origin map when present and retain their existing fallback when it is absent.

## Language server

The server is distributed as the `grammar-workbench-lsp` executable and the reusable `GrammarWorkbenchLSP` SwiftPM product. Grammar documents use language id `grammarworkbench` or `ebnf`; source documents use the associated grammar file's base name. The server now advertises incremental synchronization and applies LSP ranges as UTF-16 positions. Full-document changes remain accepted for compatibility, but stale versions and invalid ranges are ignored.

## Incremental language sessions

`GrammarWorkbenchIncrementalCompiler` remains the grammar-construction cache. Use the new `GrammarIncrementalLanguageSession` when maintaining source-language documents across edits. Its token and syntax-node identities are session-local and replace any caller-created identity heuristics; do not compare them between sessions or persist them as artifact identities.

Ranged edits now use checkpoint-based incremental lexing. Integrations using `GrammarIncrementalAnalysisCoordinator` should call `apply(documentID:edits:externalRevision:)` when the original ranges are available and retain `synchronizeDocument` for complete snapshots and unversioned saves. Analysis snapshots add `incrementalLexing`; older encoded snapshots decode with full-analysis compatibility metrics.

Successful deterministic parses now retain consumed-prefix checkpoints for subsequent edits. Analysis snapshots add `incrementalParsing`; older encoded snapshots decode with full-analysis compatibility metrics. Recovery and rejection results remain source-compatible and intentionally become full-parse boundaries for the following edit.
