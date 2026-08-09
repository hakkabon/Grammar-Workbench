# Incremental language infrastructure

Grammar Workbench exposes a stable, editor-neutral layer for maintaining analyzed source documents across changes. It complements `GrammarWorkbenchIncrementalCompiler`: the compiler caches grammar construction, while `GrammarIncrementalLanguageSession` owns versioned documents parsed by one compiled grammar.

`GrammarIncrementalAnalysisCoordinator` is the preferred application boundary. It owns a session, reconciles external editor versions and unversioned saves with monotonic internal revisions, suppresses analysis of unchanged snapshots, and centralizes document open/close and grammar-replacement lifecycles. The native app and bundled LSP use this coordinator rather than maintaining independent source-analysis state.

## Text snapshots and edits

`GrammarTextSnapshot` stores immutable text and a monotonically increasing revision. Apply one or more `GrammarTextEdit` values to create the next snapshot. Positions are zero-based UTF-16 line and column pairs, matching LSP, AppKit, and common editor protocols. Edits are applied sequentially; a nil range replaces the whole document.

Stale revisions, reversed ranges, and positions outside a line are rejected without changing session state. Each successful change reports replaced and inserted UTF-16 lengths and the resulting delta.

## Language sessions

Create `GrammarIncrementalLanguageSession` with a successful `GrammarCompilation`, then open one or more source documents. Every `GrammarIncrementalAnalysisSnapshot` contains:

- immutable text, lexing, and deterministic parse results;
- session-local stable identities for tokens and syntax subtrees;
- counts of reused, created, and removed tokens and nodes;
- the grammar revision and applied text-change summary.

Structurally unchanged tokens and subtrees keep their identities even when an earlier edit shifts their source ranges. `updateCompilation` reanalyzes all open documents after a grammar change while retaining identities wherever structure remains equal.

Identities are scoped to one session and must not be persisted as global artifact IDs. Snapshots themselves are immutable, Codable, and Sendable, making them suitable for editor models, language servers, indexes, and build daemons.

Incremental snapshots are continuously checked against clean lex/parse results. Complete reanalysis remains the correctness reference and current computational implementation; the consolidated layer provides incremental state, identity reuse, cancellation boundaries, and lifecycle ownership in preparation for region-based lexing and parsing.

## LSP synchronization

The bundled language server advertises incremental synchronization and uses the same UTF-16 edit semantics. It still accepts complete-document replacements. Stale versions and malformed ranges are ignored so diagnostics never run against a partially applied document.
