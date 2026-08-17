# Selected research preview

Phase 20 presents a small, approachable window into the Phase 19 validation machinery. It does not add new parser algorithms. Instead, it selects three questions whose results can be explained without requiring the reader to understand LR item construction first:

- **How quickly does ambiguity grow?** checks the first non-trivial Catalan cases: three operands represent two groupings and four operands represent five.
- **What does precedence hide?** shows that production parsing can select one left-associative interpretation while research exploration retains the suppressed alternative.
- **Does search order change the answer?** repeats the experiment and compares depth-first with breadth-first exploration.

Each `GrammarSelectedResearchStudy` contains its question, context, and complete `GrammarResearchProgramme`. Running it produces a `GrammarSelectedResearchPreview` with a plain-language conclusion, compact observations, limitations, and the full integrity-checked research report.

## Workbench experience

The Research workspace begins with the selected preview. Choose a question, run it, and read the conclusion and observation cards. Evidence fingerprints, case counts, and limitations remain available in a disclosure section. The existing generalized parser explorer remains below it for experiments with the current grammar and sample input.

The preview deliberately says “supports the hypothesis” rather than “proves.” A failed expectation is shown as a falsified hypothesis with the Phase 19 failure explanation; it is never hidden behind a friendly summary.

## Automation

```sh
grammar-workbench research-preview list
grammar-workbench research-preview ambiguity-growth preview.json
```

SDK hosts can negotiate `selectedResearchPreview` and provide a catalog study identifier. The returned Codable preview contains the same observations and underlying report as the native Workbench.

The release gate runs every selected study, requires each declared hypothesis to pass, bounds the catalog size, and bounds the encoded preview size. The full research-programme gate remains authoritative for broader regression validation.
