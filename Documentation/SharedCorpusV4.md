# Shared corpus v4 completion

Phase 10 completes the behavioral content of the schema introduced while the
engine family was assembled. The wire version remains 4: existing v4 adapters
continue to decode the corpus without a compatibility-only release.

## Expanded evidence

The corpus now contains 45 cases across the mini-language, JSON subset,
ambiguous expression, and predictive expression grammars. Eight bounded stress
cases add nested precedence, multi-statement input, deep parentheses, nested
objects and arrays, nullable containers, and longer ambiguous expressions.

The ambiguous-expression sequence now records the Catalan progression through
1, 2, 5, 14, and 42 derivations. Every generalized engine must return the exact
count with production-identified forest nodes. Deterministic engines must retain
the precedence-selected replay, while LL(1) must truthfully report that the
left-recursive grammar class is unsupported.

## Executable coverage

The contract validator rejects a v4 corpus that does not provide:

- all ten engine descriptors and all four grammar fixtures;
- at least 45 cases, including ten engine comparisons and eight stress probes;
- accepted, recovered, and rejected outcomes;
- both supported and unsupported LL(1) grammar classes;
- at least one case for every grammar; and
- exact generalized derivation probes at 1, 2, 5, 14, and 42.

These checks make corpus depth part of the release contract rather than a
documentation promise. Inputs remain bounded so local validation and pinned
integration runs stay practical.
