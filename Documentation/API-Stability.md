# API stability policy

Grammar Workbench 1.x separates supported deterministic tooling from parsing research.

## Stable

- `GrammarWorkbenchAPI` compilation, lexing, deterministic parsing, recovery, replay, and batch tests.
- Immutable public snapshots and schema-versioned project, artifact, and semantic-model interchange.
- `GrammarSyntaxNode`, `GrammarSemanticReducer`, declarative `GrammarSemanticActions`, semantic coverage validation, and semantic evaluation.
- `GrammarGenerator`, its registry, built-in generators, standalone Swift generation, and the SwiftPM plugin.
- `GrammarWorkbenchLSP`, the stdio server, document synchronization, diagnostics, grammar completion/definition/quick fixes, and source completion/hover/outline services.
- SLR(1), LALR(1), canonical LR(1), lexer modes, EBNF input and production-origin mapping, algorithm comparison, and artifact diffs.
- Bounded generalized LR parsing with shared-packed forests, stable node and alternative identities, saturating derivation counts, independent exploration/forest/materialization limits, per-alternative semantic evaluation, structured rejection diagnostics, search strategies, and cooperative cancellation.
- Deterministic/generalized/adaptive platform requests, common result envelopes, reproducible ambiguity selection, semantic evaluation, and bounded ordered batches.
- UI-neutral grammar-health reports, prioritized guided actions, task destinations, and validated cleanup previews.
- Structural grammar reports, explainable source-fingerprinted cleanup plans, bounded corpus generation, generalized membership comparison, and project transformation previews.
- Declarative semantic workspace schemas, immutable symbol/diagnostic/dependency snapshots, cross-document definition and reference resolution, and revision-guarded atomic rename plans.
- Versioned UTF-16 text snapshots, incremental edits, checkpoint-based relexing and deterministic reparsing, typed incremental semantic evaluation, source-aware semantic indexes, multi-document language sessions, the shared analysis coordinator, stable token/subtree identities, grammar replacement, and reuse/fallback metrics.
- Versioned project manifests, project workspaces, aggregate semantic indexes, batch-test orchestration, and configured generator targets.
- `GrammarWorkbenchSDK` envelopes, capability negotiation, codecs, async client/service APIs, and transport protocol.
- Integrated project navigator, problem, operation, and snapshot contracts for native documents and multi-document analyses.
- Stateful tooling sessions, incremental document operations, lifecycle events, request registry, and JSON-lines service-host contract.

Stable APIs follow semantic versioning. Additive source-compatible changes may occur in a minor release. Removing declarations, changing meaning, or making incompatible Codable changes requires a major version or a new interchange schema.

`GrammarWorkbenchCapabilities` exposes these maturity declarations to automated consumers.
