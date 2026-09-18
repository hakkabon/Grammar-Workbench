# Shared corpus v5

Phase 18 turns recovery from a status-level expectation into shared,
replayable evidence. Corpus schema 5 retains every version-4 engine, forest,
replay, stress, and semantic case and adds an exact recovery contract shared by
Workbench, LR-Parsing, Grammar-REPL, and Compiler.

## Recovery contract

Every `acceptedWithRecovery` case now declares:

- `expectedRecoveryEdits`, an ordered non-empty insert/delete/skip script;
- `repairedInput`, the source represented by the completed edit script; and
- `repairedTokenKinds`, the exact lexical stream for that source.

All edit positions refer to the original token stream. Applying earlier edits
must not change the coordinate system used by later edits. Insert records name
the inserted terminal, delete records name the removed terminal, and skip
records give the skipped half-open original-token range and terminal sequence.
The legacy single-edit `expectedRecovery` field remains during this schema
transition and must agree with the first compatible exact edit.

The dedicated `recovery-sequence` grammar makes the contract observable with
independent insert, delete, skip, and insert-then-skip cases. The existing JSON
trailing-comma case is also upgraded to exact evidence. Version 5 therefore
contains at least five grammars, 49 cases, and five recovered cases.

## Adapter responsibilities

- Workbench reports the complete structured edit sequence, matches its recovery
  trace and diagnostics, and reparses the declared repaired input with recovery
  disabled.
- LR-Parsing reports the same ordered script and a recovery replay event.
- Grammar-REPL exposes the same script without translating terminal identity or
  coordinates.
- Compiler reports recovery cases as explicitly unsupported; it does not claim
  parser recovery or synthesize semantic results from repaired input.

Clean accepted cases must not conceal repair edits or diagnostics. Rejected
cases may retain attempted edits as evidence, but cannot be promoted to
recovered. The ecosystem validator checks all of these distinctions.

## Validate

Build each conformance product and run:

```sh
node Scripts/validate-ecosystem-contract.mjs \
  --cli PATH/grammar-workbench \
  --lr-adapter PATH/lr-conformance \
  --compiler-adapter PATH/compiler-conformance \
  --grammar-repl-adapter PATH/grammar-repl-conformance
```

Release dependency order is LR-Parsing, Compiler, Grammar-REPL, then
Grammar-Workbench. After those releases exist, refresh their exact revisions
and versions in `Packaging/EcosystemCompatibility.json`; immutable pins remain
the integration authority.
