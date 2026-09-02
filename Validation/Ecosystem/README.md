# Shared ecosystem conformance corpus

`Corpus.json` is the engine-neutral behavioral contract shared by Grammar,
Parser, LR-Parsing, Compiler, Grammar-REPL, and Grammar-Workbench. Version one
contains normalized grammar models, token-kind sequences, and parse statuses.
Adapters therefore do not need to read another implementation's grammar syntax
or use its lexer. The `source` path on each grammar points to a Workbench fixture
and is adapter metadata; `start`, `terminals`, and `productions` are canonical.

An empty production right-hand side represents epsilon. Every other symbol must
be declared either as a terminal or as the left-hand side of a production.
Later additive fields may cover source ranges, expected symbols, reductions,
and syntax trees after every consumer has a lossless adapter.

Run the structural validation only:

```sh
node Scripts/validate-ecosystem-contract.mjs
```

Run structural validation and the Workbench adapter:

```sh
node Scripts/validate-ecosystem-contract.mjs --cli .build/release/grammar-workbench
```

Corpus cases must not contain LR state identifiers, implementation trace text,
or UI-specific diagnostic wording. The Workbench adapter verifies both the
normalized token kinds and parse status. A rejected case is conformant when the
normalized status matches even though the CLI exits unsuccessfully.
