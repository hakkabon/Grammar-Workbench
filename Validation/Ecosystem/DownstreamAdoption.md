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

LR-Parsing pins Grammar, Parser, Lexer, and GrammarDiagram, and its
`lr-conformance` executable consumes the complete normalized-token corpus with
the same bounded recovery policy as Workbench and reports normalized tree roots.
It owns LR automaton generation, stable artifact identities, conflict decisions,
tracing, recovery, checkpoints, and neutral persisted-table execution. Workbench
retains adapters only.

## Compiler

Compiler exposes a non-terminal `compiler-conformance` executable over a
dedicated adapter target. It consumes normalized token kinds through the
existing Earley integration and converts successful shared parse trees through
the compiler-owned `GeneralizedParseTreeAdapter`; compiler syntax and semantic
models remain unchanged. Successful observations include normalized tree roots,
including the start symbol for epsilon trees. Recovery is explicitly reported
as unsupported rather than skipped because the generalized-parser integration
does not expose a recovery policy. The pinned Swift 6.0 job validates every
corpus observation.

## Grammar-REPL

Grammar-REPL exposes a non-terminal `grammar-repl-conformance` executable over
`GrammarReplLib`. It constructs the shared normalized grammars and token streams,
executes its existing LALR path with bounded recovery, and reports structured
status, tree-root, diagnostic, and recovery-edit observations. Command rendering,
history, readline behavior, and session state remain outside the shared result.
The pinned Swift 6.1 job requires exact agreement for every corpus case.

## Promotion rule

Every completed item updates `Packaging/EcosystemCompatibility.json` in a
separate reviewed change. The pinned integration workflow must pass before an
adoption state or revision changes.
