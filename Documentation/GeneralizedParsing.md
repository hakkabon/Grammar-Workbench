# Generalized parser engineering

Grammar Workbench provides bounded generalized LR parsing alongside its deterministic LR runtime. It follows every applicable ACTION candidate at conflicts and merges equivalent stacks through interned symbol/span nodes. Alternative reductions become packed families in a shared-packed parse forest (SPPF), so ambiguity is retained without copying complete trees through every parser configuration.

## Public API

Use `GrammarCompilation.parseGeneralized(_:options:)` for synchronous work. Task-based callers can use `parseGeneralizedCancellable`; cancelling the task returns a result with status `cancelled` at the next configuration boundary.

Each result contains:

- `forest`, whose alternatives have stable cross-process identifiers;
- `sharedForest`, whose stable symbol/span nodes and packed families represent all discovered derivations compactly;
- the source tokens and concrete syntax trees with lexemes and ranges;
- exact configuration, step, tree, shared-node, or packed-family limits reached;
- shift, reduction, acceptance, branching, deduplication, and frontier metrics;
- a source-located rejection diagnostic with the furthest token and expected terminals.

`parseGeneralized(_:using:options:)` applies a `GrammarSemanticReducer` to every accepted alternative and preserves each forest ID beside its semantic value. This lets applications compare ASTs or evaluations before selecting an ambiguity.

Depth-first search preserves the original low-overhead discovery order. Breadth-first search is available when shallow derivations should be discovered first. Both strategies produce the same complete forest when no bound is reached.

## Operational boundaries

Generalized parsing is deliberately separate from deterministic recovery and generated parsers. Every run is bounded by configuration, step, concrete-tree, shared-node, and packed-family limits. Concrete trees are materialized only after exploration and only up to `maximumTrees`; `sharedForest.derivationCount(upTo:)` counts represented parses without enumeration and saturates at a caller-selected ceiling. A `truncated` result may still contain useful accepted alternatives and a useful partial SPPF; callers must inspect `reachedLimits` before treating either as exhaustive.

The engines remain separate internally, while `GrammarParsingPlatform` provides optional adaptive orchestration for consumers that want deterministic speed and generalized escalation at unresolved conflicts. It does not apply deterministic recovery to generalized branches or change the standalone generated-parser contract.

The release-candidate policy exercises a representative ambiguous grammar within declared bounds. The native Research workspace exposes the same status, limits, diagnostics, metrics, and stable forest alternatives.

## CLI

```text
grammar-workbench generalized-parse GRAMMAR INPUT [OUTPUT] \
  [--include-resolved] [--breadth-first] \
  [--maximum-configurations=N] [--maximum-steps=N] [--maximum-trees=N] \
  [--maximum-forest-nodes=N] [--maximum-packed-families=N]
```

`--include-resolved` explores candidates suppressed by precedence or associativity. The legacy `research-parse` command remains an alias.
