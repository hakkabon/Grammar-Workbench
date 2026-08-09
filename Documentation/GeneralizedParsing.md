# Generalized parser engineering

Grammar Workbench provides bounded generalized LR parsing alongside its deterministic LR runtime. It follows every applicable ACTION candidate at conflicts, deduplicates complete parser configurations, and preserves distinct accepted syntax trees in deterministic order.

## Public API

Use `GrammarCompilation.parseGeneralized(_:options:)` for synchronous work. Task-based callers can use `parseGeneralizedCancellable`; cancelling the task returns a result with status `cancelled` at the next configuration boundary.

Each result contains:

- `forest`, whose alternatives have stable cross-process identifiers;
- the source tokens and concrete syntax trees with lexemes and ranges;
- exact configuration, step, or tree limits reached;
- shift, reduction, acceptance, branching, deduplication, and frontier metrics;
- a source-located rejection diagnostic with the furthest token and expected terminals.

`parseGeneralized(_:using:options:)` applies a `GrammarSemanticReducer` to every accepted alternative and preserves each forest ID beside its semantic value. This lets applications compare ASTs or evaluations before selecting an ambiguity.

Depth-first search preserves the original low-overhead discovery order. Breadth-first search is available when shallow derivations should be discovered first. Both strategies produce the same complete forest when no bound is reached.

## Operational boundaries

Generalized parsing is deliberately separate from deterministic recovery and generated parsers. Every run is bounded by configuration, step, and tree limits. A `truncated` result may still contain useful accepted alternatives; callers must inspect `reachedLimits` before treating its forest as exhaustive.

The engines remain separate internally, while `GrammarParsingPlatform` provides optional adaptive orchestration for consumers that want deterministic speed and generalized escalation at unresolved conflicts. It does not apply deterministic recovery to generalized branches or change the standalone generated-parser contract.

The release-candidate policy exercises a representative ambiguous grammar within declared bounds. The native Research workspace exposes the same status, limits, diagnostics, metrics, and stable forest alternatives.

## CLI

```text
grammar-workbench generalized-parse GRAMMAR INPUT [OUTPUT] \
  [--include-resolved] [--breadth-first] \
  [--maximum-configurations=N] [--maximum-steps=N] [--maximum-trees=N]
```

`--include-resolved` explores candidates suppressed by precedence or associativity. The legacy `research-parse` command remains an alias.
