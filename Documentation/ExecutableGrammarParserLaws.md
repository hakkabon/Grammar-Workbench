# Executable Grammar and Parser Laws

Phase 15 turns two ecosystem invariants into executable, versioned evidence.
It deliberately keeps ownership below Workbench:

- `Grammar` owns canonical grammar transformations and their witnesses;
- `Parser` owns portable observation validation, metamorphic comparison, and
  fingerprinted discrepancy records; and
- `Grammar-Workbench` compiles the fixtures with its real LALR runtime and
  coordinates the two contracts.

Workbench does not reimplement either a grammar transformation or a parser-law
comparison.

## First law set

The schema-1 programme contains two exact transformations:

1. **Production permutation** changes only the order of a complete production
   set. The witness must name every production exactly once and must describe a
   nontrivial permutation.
2. **Nonterminal alpha-renaming** consistently renames the start symbol,
   production sides, and generated nonterminals. It rejects empty, colliding,
   missing, and identity renames.

The Workbench fixture accepts `a` through its normal grammar compiler and
LALR(1) parser before and after each transformation. Runtime production numbers
are projected back to the stable production identities in the Grammar witness.
Parser then validates and compares the portable tree and replay observations.

The comparison is structural rather than textual. Alpha-renamed nonterminals
are mapped back before comparison; presentation-only diagnostic wording and
engine-local forest identifiers are not semantic evidence. Status, production
identity, spans, tree topology, forest topology, diagnostic semantics,
recovery, and replay events remain observable.

## Running the programme

Run the release-facing programme with:

```sh
swift run grammar-workbench laws-validate executable-laws.json
```

The command exits unsuccessfully if any case fails. Its JSON output is a
schema-versioned `grammar-workbench-executable-law-report`; the release gate
also bounds its case count and encoded size. `Scripts/smoke-release.sh` runs the
same command against the packaged executable.

Library consumers can run the identical coordinator directly:

```swift
let report = try GrammarParserLawProgramme.run()
guard report.passed else { /* inspect report.cases */ return }
```

For an arbitrary engine observation, use Parser's `ParseLawVerifier`. A failed
evaluation can be captured with `ParseLawDiscrepancy.make`, producing a
self-contained and fingerprinted witness/input/baseline/candidate record that
can be replayed without Workbench.

## Contract and release boundary

`Packaging/EcosystemCompatibility.json` publishes the supported law names and
minimum package versions. Phase 15 requires Grammar `0.3.1` and Parser `0.3.1`;
Workbench `1.0.19` is the first release that integrates them. Those versions
must be released dependency-first before the Workbench manifest can resolve
without local package edits.

This phase proves the law machinery and one real deterministic engine path. It
does not yet claim that every parser engine satisfies every law, that language
equivalence is decidable, or that timing and allocation behavior are invariant.
Future law families should first be defined in Grammar or Parser, then adopted
by engines, the shared corpus, Grammar-REPL experiments, and finally Workbench.
