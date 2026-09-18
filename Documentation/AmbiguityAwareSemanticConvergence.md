# Ambiguity-aware semantic convergence

Phase 19 distinguishes parser ambiguity from semantic ambiguity without moving
semantic ownership out of Compiler. A parser may expose several valid syntax
trees that all evaluate to the same value, several trees with observably
different values, or a mixture of successful and failed semantic paths. Those
states are no longer collapsed into one value set or one engine-wide failure.

## Compiler evidence

Compiler semantic report schema 2 records each derivation independently with:

- a stable FNV-1a fingerprint of its adapted syntax structure and terminal
  lexemes;
- its deterministic index after fingerprint ordering; and
- exactly one semantic value or stage-qualified diagnostic.

Each engine observation classifies the evidence as
`syntacticallyUnambiguous`, `semanticallyEquivalent`,
`semanticallyDivergent`, or `unresolved`. When only some derivations evaluate,
the observation is `partiallyEvaluated`; successful values and failing paths
are both retained. Cross-engine agreement still compares the complete value
sets produced by fully evaluated engines and becomes inconclusive when partial
evidence participates.

Report schema 1 remains decodable. Its absence of derivation-level evidence is
preserved rather than retroactively inferred.

## Reproducible experiments

Grammar-REPL experiment schema 3 embeds Compiler schema-2 reports in the
experiment fingerprint. Capture and verification therefore compare the exact
syntax-to-value relationship, not only a deduplicated value set. Stable
fingerprint ordering makes the report independent of parser discovery order.

The calibration grammar parses `8-3-2` along left- and right-associated paths.
The generalized engines retain values `3` and `7`, demonstrating semantic
divergence. An engine whose syntax shape cannot satisfy the mapping records the
failure per derivation instead of erasing evidence from the other engines.

## Workbench projection

Workbench explorer schema 3 validates the Compiler-owned report but does not
re-evaluate it. The summary shows semantic agreement and ambiguity separately;
the engine inspector shows every syntax fingerprint, value, and diagnostic.
Older schema-1 and schema-2 Grammar-REPL experiments remain readable.

Release dependency order is Compiler, Grammar-REPL, then Grammar-Workbench.
The intended versions are Compiler 0.3.0, Grammar-REPL 0.8.0, and Grammar
Workbench 1.0.23. Exact repository revisions are refreshed only after the
dependency releases exist.
