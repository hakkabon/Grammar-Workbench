# Recovery truthfulness

Phase 17 turns deterministic recovery from a status label into replayable
evidence. `GrammarParseResult.recoveryEdits` records each insertion, deletion,
or synchronization skip against the original token stream. The coordinate
system therefore remains stable even when earlier repairs changed the runtime's
mutable input buffer.

## What is verified

`GrammarRecoveryTruthVerifier` fails closed when:

- a recovered result has no edit, or an ordinary accepted result hides edits;
- an edit is outside the original stream or names different deleted/skipped
  tokens;
- recovery diagnostics, runtime `recover:` trace frames, and edits differ in
  cardinality;
- an inserted terminal is absent from the recovered tree as a missing node; or
- applying the edits does not produce a clean, recovery-disabled parse.

The portable observation embeds Parser's schema-1 `ParseContractSnapshot`,
including `.recovered` status, normalized `ParseRecoveryEdit` values, and one
semantic replay recovery event per edit. Workbench coordinates this evidence;
it does not introduce a second parser contract.

## Release programme

Run:

```sh
swift run grammar-workbench recovery-validate recovery-truth.json
```

The schema-1 report covers insertion, deletion, panic synchronization, and a
diagnostic-limit failure. The first three edit their input and must reparse
strictly. The last must remain rejected while preserving the repair attempted
before the bound was reached. Case count and encoded report size are bounded by
`Packaging/ReleaseCandidate.json`, and the packaged CLI smoke test runs the same
programme.

The ecosystem compatibility contract is `0.16.0`. It fixes the report schema,
Parser contract schema, original-stream coordinate convention, supported repair
kinds, and strict-reparse requirement.
