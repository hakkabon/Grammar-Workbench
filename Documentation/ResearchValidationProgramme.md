# Research validation programme

Phase 19 turns parser research claims into portable, falsifiable programmes. A `GrammarResearchProgramme` embeds each grammar and input, states the hypothesis, declares expected deterministic and generalized outcomes, bounds the derivation count and resource-limit result, and specifies whether search-order invariance is required.

The validator checks every case through both production engines. Generalized cases run repeatedly and under depth-first and breadth-first exploration. A passing case therefore establishes all declared expectations, stable repeated evidence, and search-strategy agreement within the case's explicit resource bounds.

## Evidence and timing

`GrammarResearchCaseResult` separates two kinds of observations:

- the evidence fingerprint covers parse statuses, derivation counts, reached limits, and stable forest identities;
- the timing summary records sample count, minimum, median, 95th percentile, and maximum duration.

Timing is deliberately excluded from the evidence fingerprint. Two runs can therefore be reproducibly equivalent even though scheduler and hardware noise change their timings. Reports retain the Workbench version, public API version, platform, programme fingerprint, and aggregate evidence fingerprint.

Failed hypotheses are ordinary report data with concrete failure explanations. They do not trap or erase partial results. Invalid manifests, duplicate case identities, inverted derivation ranges, unsupported schemas, and wrong envelope kinds are rejected before execution.

## Baselines and automation

The packaged baseline covers unambiguous recognition, unresolved Catalan ambiguity, ambiguity hidden by precedence, rejection agreement, repeated identity stability, and DFS/BFS invariance.

```sh
grammar-workbench research-validate Examples/ResearchValidationProgramme.json report.json
grammar-workbench research-compare baseline.json report.json comparison.json
```

`research-validate` exits unsuccessfully if any hypothesis is falsified. `research-compare` requires the same programme fingerprint and rejects pass-to-fail regressions. Evidence changes and timing ratios remain visible even when there is no pass/fail regression.

The SDK exposes `researchValidate` with the same Codable programme and report types. Release validation bounds case count, repetitions, report size, and median runtime per case. These bounds are engineering safeguards, not claims of statistical significance.

## Scope

The programme provides repeatable regression evidence; it is not a formal proof of parser correctness. New research cases should cite their origin in `rationale` or `hypothesis`, use the smallest discriminating grammar, state expected limits explicitly, and preserve failing cases when they reveal a genuine defect.
