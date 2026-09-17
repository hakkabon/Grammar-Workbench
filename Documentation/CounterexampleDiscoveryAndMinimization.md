# Counterexample Discovery and Minimization

Phase 16 makes failures of executable Grammar and Parser laws easier to find,
preserve, and understand. It builds on the Phase-15 ownership boundary rather
than introducing another parser truth model:

- Grammar owns the transformation witness;
- Parser owns law evaluation and the fingerprinted `ParseLawDiscrepancy`; and
- Workbench owns bounded candidate generation, engine execution, search policy,
  and deterministic minimization.

Every candidate accepted by the minimizer is re-evaluated by Parser. Workbench
never infers that a smaller input still fails from the shape of the original
artifact.

## Discovery

`GrammarParserCounterexampleDiscovery.breadthFirstCandidates` produces token
sequences in stable length-first and lexical order. Callers may instead supply
an ordered corpus, fuzzing seeds, or previously recorded failures to
`discover(candidates:limits:evaluate:)`.

The evaluator returns either no failure or a Parser-owned
`ParseLawDiscrepancy`. Discovery is bounded independently by candidate count,
evaluation count, and token count. The result records whether candidate or
evaluation bounds were exhausted, so an incomplete search cannot be presented
as evidence that no counterexample exists.

## Minimization

Once a failure is found, Workbench greedily removes deterministic token chunks
while preserving the Parser discrepancy signature. The signature includes the
Grammar law and the structural paths of baseline, candidate, and comparison
violations. A final single-token deletion pass establishes `oneMinimal` when
the evaluation budget permits it.

`oneMinimal` means that deleting any one remaining token no longer reproduces
the same failure signature. It is not a claim of global minimality, semantic
minimality, or character-level minimality. The report retains both the initial
and minimized fingerprinted discrepancies for independent replay.

## Release programme

Run the bounded programme with:

```sh
swift run grammar-workbench laws-discover counterexamples.json
```

The programme exhaustively checks the small Phase-15 LALR fixture space for
both production permutation and alpha-renaming. A separately labelled synthetic
calibration injects a status disagreement around `a b a`; it must reduce
`x a b a x` to the one-minimal trigger. This calibration is a test of the
search machinery, not evidence of a Workbench parser defect.

The packaged CLI smoke test runs the same programme. Release policy bounds its
candidate count, evaluation count, and encoded report size, while ecosystem
contract `0.14.0` fixes the schema and strategy identifiers.

## Extension path

Engine repositories and Grammar-REPL can use the public evaluator boundary to
feed their native Parser contracts into the same minimizer. Likely next steps
are grammar-aware token shrinking, production reduction through Grammar-owned
witnesses, shared-corpus seed import, and automatic promotion of minimized
failures into reviewed regression cases. Those extensions should preserve the
current rule: only Parser decides whether a candidate is still the same law
failure.
