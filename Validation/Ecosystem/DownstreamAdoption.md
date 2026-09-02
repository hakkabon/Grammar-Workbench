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

LR-Parsing now pins Grammar, Parser, Lexer, and GrammarDiagram, and its
`lr-conformance` executable consumes the complete normalized-token corpus. Its
LALR statuses agree with Workbench for seven cases. The JSON trailing-comma case
is an explicit, machine-checked difference: Workbench recovers, while the LR
token-stream entry point is intentionally strict. The adoption state is
`conformance`; canonical LR ownership remains deferred until that recovery
boundary is either unified or accepted as the long-term public contract.

## Compiler

The integration coordinator checks the pinned repository externally on Swift
6.0. No Compiler source or public model is changed by that validation. At the
recorded revision, dependency resolution currently fails because Compiler asks
for Grammar on `main` while the released Parser asks for Grammar by exact
revision. The dedicated compatibility job records this as a failure, and the
adoption state remains `pending-adapter`.

- Replace Grammar and Parser branch dependencies with compatible releases.
- Add a corpus adapter without replacing compiler-specific syntax or semantic
  models.
- Record unsupported engine features as explicit adapter results rather than
  skipping cases.

## Grammar-REPL

The integration coordinator checks the pinned repository externally in a
separate Swift 6.1 job. This preserves the Swift 6.0 foundational baseline and
does not change REPL commands, rendering, or session state. At the recorded
revision, dependency resolution currently fails because GrammarDiagram is
requested both from `main` and by exact revision. The dedicated compatibility
job records this as a failure, and the adoption state remains `pending-adapter`.

- Replace all mutable Hakkabon package dependencies.
- Expose a non-terminal corpus adapter through `GrammarREPLCore`.
- Keep command rendering and readline behavior outside the shared parse result.

## Promotion rule

Every completed item updates `Packaging/EcosystemCompatibility.json` in a
separate reviewed change. The pinned integration workflow must pass before an
adoption state or revision changes.
