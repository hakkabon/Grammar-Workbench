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
- the lexer strategy, relexed UTF-16 range, prefix/suffix reuse, and fallback reason.
- the parser strategy, resume token, reparsed token count, checkpoint count, and fallback reason.
- a flat source-aware semantic index plus entry reuse, update, creation, and removal counts.

Structurally unchanged tokens and subtrees keep their identities even when an earlier edit shifts their source ranges. `updateCompilation` reanalyzes all open documents after a grammar change while retaining identities wherever structure remains equal.

Identities are scoped to one session and must not be persisted as global artifact IDs. Snapshots themselves are immutable, Codable, and Sendable, making them suitable for editor models, language servers, indexes, and build daemons.

## Incremental lexing

For a single ranged edit, lexing restarts at the last checkpoint preceding the damaged token. Checkpoints include the complete lexer-mode stack and are recorded after emitted tokens, skipped rules, and unmatched characters. Relexing stops when the changed suffix reaches an old checkpoint at the shifted offset with an identical mode stack. Unaffected prefix and suffix tokens are spliced into the result with updated ranges and indices.

Full replacement, multiple sequential edits, a previously invalid lex, the legacy whitespace-token input mode, or regular expressions whose result can depend on text outside their matched range use an explicit full-lex fallback. `GrammarIncrementalLexingMetrics` makes the strategy and reason observable. Unicode positions, multiline tokens, skipped mode transitions, and push/pop/begin mode stacks use the same checkpoint rules.

Incremental lex results are continuously checked against clean lexing.

## Incremental deterministic parsing

The deterministic LR runtime records a resumable checkpoint immediately after each shifted token. A checkpoint contains the consumed-token index, parser state and symbol stacks, partial parse-tree stack, completed step count, and replay frames. Capturing after a shift is significant: reductions at the same cursor depend on the next lookahead and are therefore replayed whenever that token changes.

After lexing, the session compares token kind, lexeme, and lexer mode to find the unchanged prefix. Parsing resumes from the corresponding checkpoint and reparses the affected suffix. Retained replay frames are rebased onto the new token stream so traces, syntax trees, diagnostics, recovery decisions, ranges, and step-limit behavior remain equal to a clean parse.

A previously recovered, rejected, conflicted, looping, or lexically invalid result is not used as a resume source. Grammar replacement and missing checkpoints also perform an explicit full-parse fallback. `GrammarIncrementalParsingMetrics` reports the selected strategy, resume boundary, work performed, available checkpoints, and fallback reason. Clean incremental results and recovery reached after a safe checkpoint are checked against full deterministic parsing in the test suite.

## Incremental semantics and indexing

Every snapshot publishes `semanticIndex`, a flat source-ordered view of its stable syntax nodes. Entries retain parent identity, symbol, production, terminal metadata, depth, recovery state, and source range. Callers can query by symbol, production, identity, or UTF-16 source offset without walking the concrete tree. `incrementalIndexing` distinguishes entries reused exactly from stable entries whose source metadata changed, as well as additions and removals.

`GrammarIncrementalSemanticEvaluator` layers application semantics over these identities while preserving the reducer's concrete `Value` type. It caches terminal, missing-token, and production results and reevaluates only nodes whose complete source-aware representation changed. This conservative equality rule keeps reducers that inspect locations correct: an edit after a subtree can reuse it, while an edit that shifts its range reevaluates it. Cached descendants remain available even when an entire parent subtree is reused.

Semantic evaluation is transactional: a thrown reducer error leaves the preceding cache intact. Rejected parses do not evaluate. Grammar revision changes invalidate cached values, and `updateCompilation` installs replacement production metadata before evaluating refreshed snapshots. Metrics report reused, evaluated, removed, and grammar-invalidated values.

## LSP synchronization

The bundled language server advertises incremental synchronization and forwards accepted ranged edits to the shared coordinator before its diagnostic debounce. It still accepts complete-document replacements. Stale versions and malformed ranges are ignored so diagnostics never run against a partially applied document.
