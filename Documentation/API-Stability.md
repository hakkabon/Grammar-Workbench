# API stability policy

Grammar Workbench 1.x separates supported deterministic tooling from parsing research.

## Stable

- `GrammarWorkbenchAPI` compilation, lexing, deterministic parsing, recovery, replay, and batch tests.
- Immutable public snapshots and schema-versioned project, artifact, and semantic-model interchange.
- `GrammarSyntaxNode`, `GrammarSemanticReducer`, declarative `GrammarSemanticActions`, semantic coverage validation, and semantic evaluation.
- `GrammarGenerator`, its registry, built-in generators, standalone Swift generation, and the SwiftPM plugin.
- `GrammarWorkbenchLSP`, the stdio server, document synchronization, diagnostics, grammar completion/definition/quick fixes, and source completion/hover/outline services.
- SLR(1), LALR(1), canonical LR(1), lexer modes, EBNF input and production-origin mapping, algorithm comparison, and artifact diffs.
- Bounded generalized LR parsing, stable alternative identities, per-alternative semantic evaluation, structured rejection and limit diagnostics, search strategies, and cooperative cancellation.
- Versioned UTF-16 text snapshots, incremental edits, checkpoint-based relexing, multi-document language sessions, the shared analysis coordinator, stable token/subtree identities, grammar replacement, and reuse/fallback metrics.

Stable APIs follow semantic versioning. Additive source-compatible changes may occur in a minor release. Removing declarations, changing meaning, or making incompatible Codable changes requires a major version or a new interchange schema.

`GrammarWorkbenchCapabilities` exposes these maturity declarations to automated consumers.
