# Grammar and parser ecosystem contract

This document defines ownership, compatibility, and release coordination for
the Hakkabon grammar and parser repositories. It is the normative coordination
policy for the revisions recorded in
`Packaging/EcosystemCompatibility.json`. Repository-specific API policies may
make stronger promises but must not contradict this contract.

## Ownership

| Contract | Canonical owner | Notes |
| --- | --- | --- |
| Grammar symbols, productions, precedence, grammar loading, and grammar analysis | `Grammar` | Must not depend on a parser implementation or application. |
| Generic parser protocols, syntax trees, parse results, and parser diagnostics | `Parser` | Engine-neutral contracts only. |
| LR construction and execution | `LR-Parsing` and `Grammar-Workbench`, temporarily | Neither implementation is canonical until differential conformance is demonstrated. |
| Compiler syntax and semantic models | `Compiler` | Compiler ASTs remain distinct from engine-neutral parse trees. |
| REPL commands, command history, and transcripts | `Grammar-REPL` | Terminal presentation and readline integration are not shared contracts. |
| Portable interchange, editor services, SDK envelopes, and language-kit tooling | `Grammar-Workbench` | May adapt upstream contracts but must not redefine their semantics. |

A type moves to a canonical owner only after all affected repositories can use
an adapter without information loss. Moving a type and removing the old API in
one release is not permitted.

## Compatibility promises

The ecosystem distinguishes four forms of compatibility:

1. **Source compatibility**: a documented public consumer continues to compile.
2. **Behavioral compatibility**: the shared conformance corpus produces the
   same normalized acceptance, diagnostic, and tree results.
3. **Interchange compatibility**: a versioned serialized envelope continues to
   decode according to its schema rules.
4. **Toolchain compatibility**: every revision in the compatibility manifest
   builds with a supported Swift toolchain and platform.

Stable releases use semantic versioning. Additive source-compatible changes
may be minor releases. Removal, changed meaning, or an incompatible serialized
shape requires a major release or a new schema. Before 1.0, an incompatible
change requires a minor release. A public declaration must be deprecated for at
least one release before removal unless it is an immediate security correction.

No release may claim ecosystem compatibility solely because its repository-local
tests pass. It must also pass the pinned integration workflow at an exact set of
revisions.

## Dependency rules

- Foundational packages must not depend on downstream applications.
- Release and compatibility branches must not depend on a mutable branch such
  as `main`. They use a compatible tagged version or an exact revision.
- A compatibility manifest is immutable evidence. Updating one revision
  requires running the complete integration workflow and reviewing the result.
- Parser-engine details such as LR state numbers, table layout, trace wording,
  or recovery implementation are not shared contracts unless the corpus schema
  explicitly promotes them.
- Compiler semantic ASTs, UI diagnostics, and terminal rendering remain wrapper
  contracts. They adapt the shared parser contracts rather than expanding them.

## Supported baseline

The contract-release baseline uses Swift 6.0 for integration. Individual
packages may retain an older `swift-tools-version` and broader deployment
targets. A package requiring a newer compiler is recorded in the manifest and
is tested in a separate compatible job; it must not silently raise the baseline
for foundational packages.

## Release process

1. Update and validate the shared corpus without implementation-specific data.
2. Test the proposed foundational release against pinned downstream revisions.
3. Publish Grammar, then update and publish Parser against that Grammar release.
4. Update the compatibility manifest to the released tags or exact commits.
5. Validate LR-Parsing, Compiler, Grammar-REPL, and Grammar-Workbench at those
   revisions.
6. Publish the manifest and conformance report with the release notes.

Grammar and Parser should initially use pre-1.0 releases while diagnostic and
syntax-tree convergence is in progress. Selecting a canonical LR engine is
explicitly deferred until the two engines agree on the shared differential
corpus or every remaining difference is accepted and documented.

## Adoption states

Each manifest entry has an adoption state:

- `pinned`: the repository builds at the exact revision.
- `conformance`: it also provides a shared-corpus adapter.
- `pending-adapter`: its exact revision is recorded, but corpus integration is
  tracked as downstream work.

`pending-adapter` is visible debt, not a passing conformance claim.
