# Research-quality distribution

Phase 14 makes the existing validation programme independently distributable.
It does not add a new parser, benchmark, or claim. It packages the falsifiable
hypotheses and evidence already owned by `GrammarWorkbenchCore` with enough
provenance to cite, inspect, reproduce, and reject a corrupted result.

## Create and verify a bundle

Build the command-line product, then run:

```sh
grammar-workbench research-package \
  Examples/ResearchValidationProgramme.json \
  Packaging/EcosystemCompatibility.json \
  LICENSE \
  Grammar-Workbench-Research-1.0.21

grammar-workbench research-package-verify \
  Grammar-Workbench-Research-1.0.21
```

The output directory must be new or empty. Verification fails on a missing,
modified, or undeclared file and checks the links among the programme, report,
Workbench version, public API, evidence fingerprint, and ecosystem contract.
An archive can be made from the verified directory without changing the
directory contract.

## Bundle contract

`manifest.json` conforms to
`Validation/Research/DistributionManifest.schema.json` and inventories these
six payload files with byte counts and SHA-256 digests:

- `programme.json` contains explicit hypotheses, inputs, bounds, and expected
  outcomes;
- `report.json` contains the observed results, per-case evidence, and timing;
- `ecosystem.json` pins every participating repository to a version and full
  revision;
- `README.md` records the reproduction protocol and bundle interpretation;
- `CITATION.cff` supplies citation metadata; and
- `LICENSE.txt` states the distribution terms.

The repository also publishes a root `CITATION.cff` for the software release.
macOS and Linux release packaging each produce a separately checksummed research
archive and include it in release provenance.

## Evidence and timing

The evidence fingerprint covers semantic observations and excludes elapsed
time. Repeating the programme on another supported host should therefore retain
the evidence identity even when its timing distribution changes. The full
report preserves platform and timing information so performance observations
remain attributable rather than being presented as portable facts.

The bundle establishes integrity, provenance, and reproducibility for the
declared cases. It is not a formal proof of parser correctness, an exhaustive
language corpus, or evidence of statistical significance beyond the recorded
repetitions. New claims belong in a new programme or schema-compatible bundle;
historical bundles remain immutable.
