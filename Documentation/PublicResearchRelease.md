# Public research release

Phase 30 makes the complete research surface independently archivable. It does
not introduce a new parser or enlarge an existing correctness claim. Instead,
it binds the already executable evidence to one source revision, one pinned
ecosystem, the shared corpus, the capability ledger, and an explicit statement
of what the evidence does and does not support.

## Create and verify

The macOS and Linux release scripts create the archive automatically. A local
release build can produce the same directory contract with:

```sh
grammar-workbench public-research-release \
  Examples/ResearchValidationProgramme.json \
  Examples/ResearchBenchmarkProtocol.json \
  Packaging/EcosystemCompatibility.json \
  Packaging/EcosystemCapabilities.json \
  Validation/Ecosystem/Corpus.json \
  LICENSE SOURCE_REVISION Grammar-Workbench-Research-1.0.31

grammar-workbench public-research-release-verify \
  Grammar-Workbench-Research-1.0.31
```

`SOURCE_REVISION` must be the full 40-character revision from which the binary
was built. Packaging supplies it from the reviewed release revision or `HEAD`.

## Contents and evidence identities

The schema-1 manifest inventories eleven files with byte counts and SHA-256:

- executable validation programme and its passing semantic report;
- selected-study benchmark protocol and the complete report with raw timings;
- shared conformance corpus v5;
- ecosystem capability ledger and exact repository pins;
- a machine-readable index of three supported claims and five non-claims;
- reproduction guidance, citation metadata, and the MIT license.

The verifier checks more than file integrity. Programme, semantic evidence,
benchmark protocol, nested study evidence, measurements, software version,
corpus version, capability-ledger version, and ecosystem contract must agree
with the top-level manifest. Unknown, missing, oversized, or modified files fail
closed.

## Interpretation

The validation fingerprint is portable semantic evidence. The benchmark
measurement fingerprint also covers the host and raw timings. Cross-host timing
comparison and parser-engine ranking are deliberately outside this bundle's
claims; engine attribution remains with the Phase 29 engine-owned
microbenchmarks. The release is bounded empirical evidence, not a formal proof
or an exhaustive test of all context-free grammars.
