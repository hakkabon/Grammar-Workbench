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

Run the complete pinned cross-repository workflow with the Swift version named
by `Packaging/EcosystemCompatibility.json`:

```sh
Scripts/validate-ecosystem-integration.sh
```

The workflow checks out every non-Workbench repository at its full manifest
revision, verifies the detached checkout, gives each package an isolated build
directory, runs its test suite, and finally runs the Workbench corpus adapter.
Set `ECOSYSTEM_REPORT_PATH` to retain immutable JSON evidence containing the
manifest digest and tested revisions. For offline development,
`ECOSYSTEM_REPOSITORY_MIRROR_ROOT` may name a directory containing local clones;
the same exact commit checks still apply. Developers may set
`ECOSYSTEM_ALLOW_TOOLCHAIN_MISMATCH=1` for an additional local toolchain check;
CI never sets it, so the manifest baseline remains mandatory evidence.

`ECOSYSTEM_REPOSITORIES` selects a space-separated subset for an independent
compatibility job, and `ECOSYSTEM_SKIP_WORKBENCH=1` omits the coordinator build
from that job. CI uses these controls to evaluate Compiler on Swift 6.0 and
Grammar-REPL on Swift 6.1. A dependency-resolution failure is a compatibility
failure: the coordinator never rewrites a downstream manifest to make it pass.

Corpus cases must not contain LR state identifiers, implementation trace text,
or UI-specific diagnostic wording. The Workbench adapter verifies both the
normalized token kinds and parse status. A rejected case is conformant when the
normalized status matches even though the CLI exits unsuccessfully.
