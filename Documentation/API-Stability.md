# API stability policy

Grammar Workbench 1.x separates supported deterministic tooling from parsing research.

## Stable

- `GrammarWorkbenchAPI` compilation, lexing, deterministic parsing, recovery, replay, and batch tests.
- Immutable public snapshots and schema-versioned project, artifact, and semantic-model interchange.
- `GrammarSyntaxNode`, `GrammarSemanticReducer`, declarative `GrammarSemanticActions`, semantic coverage validation, and semantic evaluation.
- `GrammarGenerator`, its registry, built-in generators, standalone Swift generation, and the SwiftPM plugin.
- `GrammarWorkbenchLSP`, the stdio server, document synchronization, diagnostics, grammar completion/definition/quick fixes, and source completion/hover/outline services.
- SLR(1), LALR(1), canonical LR(1), lexer modes, EBNF input and production-origin mapping, algorithm comparison, and artifact diffs.

Stable APIs follow semantic versioning. Additive source-compatible changes may occur in a minor release. Removing declarations, changing meaning, or making incompatible Codable changes requires a major version or a new interchange schema.

## Experimental

- `parseGeneralized` and all `GrammarGeneralized*` declarations.
- Parse-forest exploration behavior, limits, ordering, and research metrics.

Experimental declarations are production-isolated and may evolve between minor releases. Their Codable representation is intended for diagnostics and experiments, not persistent storage.

`GrammarWorkbenchCapabilities` exposes these maturity declarations to automated consumers.
