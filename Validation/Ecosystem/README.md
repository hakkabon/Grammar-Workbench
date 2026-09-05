# Shared ecosystem conformance corpus

`Corpus.json` is the engine-neutral behavioral contract shared by Grammar,
Parser, LR-Parsing, Compiler, Grammar-REPL, and Grammar-Workbench. Version two
contains 29 cases with normalized grammar models, stable production IDs,
precedence declarations, token-kind sequences, parse statuses, tree roots,
ambiguity declarations, first-diagnostic expectations, and successful recovery
edits.
Adapters therefore do not need to read another implementation's grammar syntax
or use its lexer. The `source` path on each grammar points to a Workbench fixture
and is adapter metadata; `start`, `terminals`, and `productions` are canonical.

An empty production right-hand side represents epsilon. Every other symbol must
be declared either as a terminal or as the left-hand side of a production.
Production IDs are stable corpus identities rather than engine table indices.
Version two intentionally stops at normalized tree roots: exact source spans,
reduction sequences, and complete trees remain future fields until every shared
parser tree retains production identity losslessly.

`LRConvergence.json` is the reviewed differential policy. Exact Workbench/LR
status agreement is the default. Every mismatch must name a corpus case, both
observed statuses, and a reason. The validator also rejects stale exceptions
after the implementations begin to agree.

`DependencyBoundaries.json` classifies the direct package graph by owner and
layer. `Scripts/audit-dependency-boundaries.mjs` evaluates real SwiftPM manifests
and rejects unreviewed edges, reverse ownership, mutable branches, local package
dependencies, duplicates, and stale allowlists. See
`Documentation/DependencyBoundaryAudit.md` for the scope and promotion rule.

Run the structural validation only:

```sh
node Scripts/validate-ecosystem-contract.mjs
```

Run structural validation and the Workbench adapter:

```sh
node Scripts/validate-ecosystem-contract.mjs --cli .build/release/grammar-workbench
```

Run structural validation and the LR differential adapter:

```sh
node Scripts/validate-ecosystem-contract.mjs --lr-adapter /path/to/lr-conformance
```

Run the Compiler adapter, including explicit unsupported-capability records:

```sh
node Scripts/validate-ecosystem-contract.mjs --compiler-adapter /path/to/compiler-conformance
```

Run the Grammar-REPL adapter, requiring exact status and recovery agreement:

```sh
node Scripts/validate-ecosystem-contract.mjs --grammar-repl-adapter /path/to/grammar-repl-conformance
```

Run the complete pinned cross-repository workflow with the Swift version named
by `Packaging/EcosystemCompatibility.json`:

```sh
Scripts/validate-ecosystem-integration.sh
```

The workflow checks out every non-Workbench repository at its full manifest
revision, verifies the detached checkout, gives each package an isolated build
directory, runs its test suite, builds the pinned LR, Compiler, and Grammar-REPL
adapters, and finally validates all available corpus observations through the
convergence policy.
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
or UI-specific diagnostic wording. The Workbench adapter verifies normalized
token kinds, status, tree root, first diagnostic, and successful recovery. The
other adapters verify status and tree root for supported behavior. A rejected
case is conformant when the normalized status matches even though the CLI exits
unsuccessfully.
