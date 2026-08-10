# Grammar analysis and transformation

Phase 8 turns grammar hygiene from a collection of diagnostics into a reusable engineering library. It complements the classical analyses and transformations in the `Grammar` dependency while retaining the Workbench source ranges, parser artifacts, test cases, and generalized runtime needed for interactive validation.

The design is informed by Douglas W. Jones's composable `gtools` model and the later GrammarToolbox rewrite: analysis, transformation, and presentation remain separable operations over one grammar representation. Grammar Workbench does not import a second competing grammar model; it exposes the shared facts through immutable reports and adds source- and behavior-aware validation around transformations.

## Structural analysis

`GrammarEngineering.analyze(_:)` returns an immutable, Codable `GrammarStructuralAnalysis` containing:

- production, symbol, dependency, nullability, and duplicate statistics;
- reachable, unreachable, productive, unproductive, and nullable nonterminals;
- terminal usage;
- direct and indirect left recursion;
- dependency edges and strongly connected components;
- duplicate production groups with every production identity;
- sorted FIRST and FOLLOW sets.

The Guide shows a compact version under **Grammar structure**. The full report is available through `grammar-workbench grammar-analyze GRAMMAR [OUTPUT]`.

## Explainable transformation plans

`GrammarEngineering.plan(_:for:)` currently plans three source-preserving Workbench-notation cleanups:

- duplicate production declarations whose repeated alternative is on a separate declaration line;
- productions unreachable from the start symbol;
- non-start productions that cannot derive terminal input.

A plan records a source fingerprint, affected line ranges, symbols, a reason for every operation, and its assurance classification. `apply(_:to:)` rejects stale source rather than applying offsets to a changed document. Same-line duplicate alternatives are deliberately left untouched because deleting their declaration would also delete the original alternative.

Guide previews delegate to this library. They never edit a document until the validated result is explicitly applied.

## Bounded behavioral comparison

Equivalence of arbitrary context-free grammars is undecidable, so Grammar Workbench does not label a finite test as proof. `GrammarEngineering.compare` instead produces a `GrammarBehaviorComparison` over:

1. caller-supplied examples or project sources; and
2. a bounded breadth-first corpus derived from the original grammar when it uses token-style input.

Both grammars are recognized with bounded generalized parsing, so duplicate or ambiguous derivations are treated as language membership rather than deterministic-table accidents. Reports retain the before/after outcome for every input, concrete membership discrepancies, generator bounds, and whether generation reached a limit.

`GrammarEngineering.execute` combines plan application, compilation, artifact diffing, behavioral comparison, and saved grammar tests. `isSafeToApply` requires successful compilation, agreement on the bounded corpus, and a passing post-transformation test suite.

Integrated-lexer grammars use supplied samples and tests but do not synthesize raw source from token names. Project workspaces automatically contribute every embedded source and saved test. The CLI command

```sh
grammar-workbench grammar-transform unreachable Grammar.grammar Cleaned.grammar
```

applies a transformation only after its generated comparison corpus finds no language-membership difference.
