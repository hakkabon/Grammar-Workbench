# Reproducible Grammar-REPL experiments

Phase 11 makes an interactive ten-engine comparison durable without moving
REPL behavior into Grammar Workbench. Grammar-REPL 0.6.0 owns a versioned,
self-contained experiment artifact and the code that captures and verifies it.

## Recorded contract

An experiment records:

- the complete parser-significant grammar and input;
- the canonical selected-engine order;
- LR precedence, production overrides, and conflict-resolution policy;
- supported and unsupported engine capability decisions;
- normalized parse contracts, portable forests and replay events;
- stable derivation fingerprints and cross-engine agreement; and
- its producer version, schema version, and semantic fingerprint.

Source paths, command history, terminal formatting, and timestamps are excluded.
They do not affect parser behavior and would make the same experiment differ
between machines. The schema-1 fingerprint uses FNV-1a over sorted semantic
material rather than Swift's process-randomized `Hasher`.

## Replay boundary

Grammar-REPL exposes interactive `:experiment save`, `show`, and `verify`
commands. The separate `grammar-repl-experiment` executable provides `show` and
`verify` for scripts and CI. Verification first rejects malformed or tampered
artifacts, then reconstructs the recorded settings, reruns each engine, and
compares availability, unsupported rationale, normalized contract, derivation
fingerprints, and overall agreement.

Phase 12 adds a bounded, read-only Workbench projection for exploration. It
decodes the engine evidence needed for comparison, forest visualization, and
replay, but does not reconstruct the grammar, recompute the fingerprint, or run
the engines. The UI therefore labels the fingerprint as recorded evidence and
directs users to `grammar-repl-experiment verify` for semantic verification.

Schema 2 can also embed a versioned Compiler AST mapping and Compiler-owned
per-engine values, failures, derivation counts, and semantic agreement. The
Workbench presents that evidence without evaluating it; schema-1 syntax-only
experiments remain readable.

The ecosystem manifest pins Grammar-REPL 0.6.0 and Compiler 0.2.0 and publishes the minimum
schema-2, `fnv1a64`, verifier-product, and explorer-projection compatibility
facts. Pinned integration builds both the conformance adapter and experiment
verifier, ensuring the research surface remains independently consumable
without reversing repository dependencies.
