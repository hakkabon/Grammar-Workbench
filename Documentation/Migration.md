# Compatibility and migration

## Semantic language kits

Existing project manifests and separate semantic-schema files remain valid. Adopt a kit when the same grammar and semantic policy must be shared by more than one project or tool. The kit format is additive: create a `GrammarSemanticLanguageKitManifest`, move the existing grammar and schema into it, add a namespaced identifier, version, file extensions, and conformance tests, then run `grammar-workbench kit-validate`. Production identities in semantic selectors are checked during kit compilation.

## Project documents

Schema-1 projects remain readable. They default to workbench grammar notation and an empty test suite where those fields were absent. New exports use schema 2.

The native `GrammarWorkbenchInterchange` remains the single-document app format. Multi-document automation should adopt the separate `GrammarProjectManifest` envelope rather than attempting to extend native document JSON. Its schema starts at 1 and explicitly records its envelope kind and required public API version.

## Artifact interchange

Schema-1 artifact envelopes remain readable and normalize to schema 2. Consumers should validate both envelope and public API versions and should not persist state or production identifiers across grammar edits.

## Parse results

Older parse-result JSON without `syntaxTree` remains decodable. Consumers should continue accepting the rendered `tree` field while adopting structured syntax nodes.

## Generalized parser engineering

`grammar-workbench generalized-parse` is the supported spelling of the generalized parser command. `research-parse` remains as a compatibility alias. Existing `parseGeneralized` calls remain source-compatible; results now also expose a structured `forest`, stable alternative IDs, exact `reachedLimits`, rejection `syntaxDiagnostics`, and expanded action metrics. Use `parseGeneralizedCancellable` in task-based integrations that need cooperative cancellation.

Generalized results now also expose `sharedForest`. Existing `forest` alternatives and semantic-evaluation APIs remain source-compatible, but concrete alternatives are bounded views materialized from the SPPF. Consumers that need ambiguity counts or compact structural inspection should use `sharedForest.derivationCount(upTo:)`, `nodes`, and packed `families`. Older result JSON without `sharedForest` decodes with an empty shared forest; the concrete alternatives remain available.

Existing deterministic and generalized entry points remain supported. Applications that previously selected between them manually may adopt `GrammarParsingPlatform` with `.adaptive` mode. The platform preserves an escalated deterministic conflict result and never treats a policy-selected ambiguous tree as uniquely accepted. `GrammarCompilation.evaluate(_:using:)` is now public for callers that maintain their own forest-selection policy.

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

Analysis snapshots now include `semanticIndex` and `incrementalIndexing`. Older encoded snapshots rebuild the index from their retained incremental syntax tree and receive compatibility metrics. Applications that repeatedly run a `GrammarSemanticReducer` can adopt `GrammarIncrementalSemanticEvaluator`; call its `updateCompilation` together with the language session's grammar replacement so production metadata and cache invalidation remain synchronized.

## Stateful tooling service

Schema-one stateless SDK requests continue to work unchanged. Stateful clients
should negotiate `sessionOpen`, retain the returned session identifier, correlate
responses by `requestID`, and treat event sequence numbers as session-local.
JSON-lines responses may arrive out of request order.

## Grammar analysis and transformations

Existing front-end diagnostics and `GrammarAnalysisSnapshot` remain source-compatible. Consumers that need hygiene, dependency cycles, left recursion, duplicate groups, or transformation planning may adopt `GrammarEngineering` incrementally. Transformation plans are source-fingerprinted and do not mutate a compilation or project workspace. Treat `GrammarBehaviorComparison.agreesOnCorpus` as bounded evidence, not a proof of global grammar equivalence.
