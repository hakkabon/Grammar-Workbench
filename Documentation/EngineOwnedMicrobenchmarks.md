# Engine-owned microbenchmarks

Phase 29 separates algorithm attribution from Workbench's Phase 21 whole-study
macrobenchmark. Parser 0.4.1 owns a neutral schema-1 suite/report envelope and a
fail-closed runner. Each parser repository owns its fixture, scale, measured
boundary, correctness evidence, and executable.

## Ownership

| Repository | Release | Executable | Owned variants |
|---|---:|---|---|
| LL-Parsing | 0.1.2 | `ll-microbenchmark` | LL(1) |
| Earley-Parser | 0.2.1 | `earley-microbenchmark` | Earley |
| Earley-TableParser | 0.2.1 | `earley-table-microbenchmark` | simple and extended lookahead |
| CYK-Parser | 0.2.1 | `cyk-microbenchmark` | CYK over pre-normalized parser state |
| RNGLR-Parser | 0.2.3 | `rnglr-microbenchmark` | RNGLR ambiguous forest construction |
| LR-Parsing | 0.2.5 | `lr-microbenchmark` | LR(0), SLR, LALR, and canonical LR(1) |

The owner version, engine identity, grammar/input fingerprint, workload scale,
and prose boundary are part of the suite fingerprint. Every run first captures
an unmeasured correctness observation. Warmups and measured iterations must
produce the same evidence fingerprint and deterministic counters or the run
fails without publishing timings.

## Running and inspecting

Build an engine in release mode and write its report, for example:

```sh
swift run -c release earley-microbenchmark earley.json
swift run -c release lr-microbenchmark lalr lalr.json
```

Workbench 1.0.30 can inspect reports without linking or executing their
engines:

```sh
grammar-workbench engine-benchmark-inspect earley.json lalr.json \
  --output=summary.json
grammar-workbench engine-benchmark-compare baseline.json candidate.json
```

The native Research workspace accepts multiple report documents and displays
their owners, declared boundaries, medians, 95th percentiles, raw sample counts,
and evidence identities.

## Comparison policy

Cross-engine rows are descriptive. They do not automatically become a speed
race: each implementation currently owns a distinct native result boundary.
The comparison command emits median ratios only when the complete suite
fingerprint, build configuration, operating system, architecture, processor
inventory, physical memory, and correctness evidence match. This supports
longitudinal regression analysis of one engine without presenting unrelated
workloads as equivalent.

The existing research benchmark remains the authoritative macrobenchmark for
the complete Workbench study workflow. Engine reports complement it; they do
not replace semantic, corpus, forest, replay, or recovery conformance.
