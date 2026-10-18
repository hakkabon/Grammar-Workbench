# Benchmark and publication protocol

Phase 21 turns the selected research studies into a repeatable macrobenchmark
without confusing speed with correctness. Every run first produces the complete
Phase 20 study report. Measured iterations are accepted only while each study's
semantic evidence remains identical to that baseline.

## Run and compare

Build the executable in the configuration declared by the protocol, keep the
host otherwise idle, and run:

```sh
swift build -c release
.build/release/grammar-workbench research-benchmark \
  Examples/ResearchBenchmarkProtocol.json benchmark.json
```

The report retains every raw duration plus minimum, median, 95th percentile,
and maximum summaries. Warmups are never samples. `research-benchmark-compare`
emits descriptive median ratios only when protocol fingerprints, semantic
evidence fingerprints, and environment identities match exactly:

```sh
grammar-workbench research-benchmark-compare baseline.json candidate.json
```

An absent ratio is intentional: unlike build configurations, operating systems,
architectures, processor inventories, or memory sizes do not form a defensible
performance comparison. Even compatible ratios do not assert statistical
significance; the raw observations remain available for independent analysis.

## Publish and verify

```sh
grammar-workbench research-benchmark-package \
  Examples/ResearchBenchmarkProtocol.json \
  Packaging/EcosystemCompatibility.json \
  LICENSE Grammar-Workbench-Benchmark-1.0.27

grammar-workbench research-benchmark-package-verify \
  Grammar-Workbench-Benchmark-1.0.27
```

The publication contains the canonical protocol, benchmark report (including
the complete correctness study), exact ecosystem pins, citation metadata,
license, reproduction guidance, and a SHA-256 manifest. The semantic evidence
fingerprint is independent of timings. The measurement fingerprint covers the
protocol, recorded environment, semantic evidence, and exact raw samples.

## Scope

This is a whole-study macrobenchmark. It measures compilation, deterministic
and generalized parsing, forest inspection, and the study's reproducibility
checks together. It is suitable for tracking the shipped research workflow,
not for attributing time to an individual parser primitive. Such attribution
would require a separate engine-owned microbenchmark protocol.
