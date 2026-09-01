# Downstream adoption ledger

The coordination repository can pin and test downstream revisions, but each
repository owns changes to its public manifest and adapter. The following work
must land in the owning repository before its manifest entry advances.

## Grammar

- Replace mutable production dependencies with tagged ranges or exact revisions.
- Add an external public-API consumer fixture.
- Publish the initial pre-1.0 semantic-versioned release.

## Parser

- Depend on the released Grammar baseline instead of `main`.
- Document `SyntaxTree`, `ParseDiagnostic`, `ParseStatus`, parse results, and
  parser protocols as its initial engine-neutral contract.
- Add an external consumer fixture and publish the corresponding pre-1.0 release.

## LR-Parsing

- Replace Grammar, Parser, Lexer, and GrammarDiagram branch dependencies.
- Add a corpus adapter that emits the normalized status contract.
- Advance from `pending-adapter` to `conformance` only when the adapter passes
  the complete corpus at the pinned revision.

## Compiler

- Replace Grammar and Parser branch dependencies with compatible releases.
- Add a corpus adapter without replacing compiler-specific syntax or semantic
  models.
- Record unsupported engine features as explicit adapter results rather than
  skipping cases.

## Grammar-REPL

- Replace all mutable Hakkabon package dependencies.
- Expose a non-terminal corpus adapter through `GrammarREPLCore`.
- Keep command rendering and readline behavior outside the shared parse result.

## Promotion rule

Every completed item updates `Packaging/EcosystemCompatibility.json` in a
separate reviewed change. The pinned integration workflow must pass before an
adoption state or revision changes.
