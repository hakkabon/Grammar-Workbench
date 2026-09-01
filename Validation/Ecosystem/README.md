# Shared ecosystem conformance corpus

`Corpus.json` is the engine-neutral behavioral contract shared by Grammar,
Parser, LR-Parsing, Compiler, Grammar-REPL, and Grammar-Workbench. Version one
asserts normalized parse status. Later additive fields may cover source ranges,
expected symbols, reductions, and syntax trees after every consumer has a
lossless adapter.

Run the structural validation only:

```sh
node Scripts/validate-ecosystem-contract.mjs
```

Run structural validation and the Workbench adapter:

```sh
node Scripts/validate-ecosystem-contract.mjs --cli .build/release/grammar-workbench
```

Corpus cases must not contain LR state identifiers, implementation trace text,
or UI-specific diagnostic wording. A rejected case is conformant when the
normalized status matches even though the CLI exits unsuccessfully.
