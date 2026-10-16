# Research study explorer

Phase 20 turns the selected research previews into one reproducible study
artifact. The explorer runs every declared study, preserves each underlying
validation report, and fingerprints the complete evidence set. A friendly
conclusion therefore never replaces the parser evidence from which it was
derived.

The initial catalog asks three bounded questions:

- how ambiguity grows for small expression grammars;
- what alternatives precedence and associativity suppress; and
- whether repeated and differently ordered searches preserve the same forest.

The native Research workspace can run either one preview or the complete
suite. Its suite summary shows supported studies, case and derivation counts,
reproducibility, and the aggregate evidence identity. Selecting a study drills
back into its hypothesis, observations, limitations, case evidence, and
programme/report fingerprints.

## Artifact contract

`GrammarResearchStudyExplorerReport` schema 1 embeds the complete selected
catalog. `GrammarResearchStudyExplorerCodec` rejects missing, duplicate, or
unknown studies; invalid nested research reports; conclusions inconsistent
with their evidence; and mismatched aggregate fingerprints. Catalog order does
not affect the fingerprint.

The artifact is intentionally evidence-oriented. Timing remains descriptive,
not a scientific claim, and the small catalog supports its hypotheses only
within the declared grammars, inputs, repetitions, and resource bounds.

## Automation and embedding

```sh
grammar-workbench research-study study.json
```

SDK clients use the `researchStudyExplorer` operation. Both interfaces return
the same Codable artifact as the native Workbench. The release gate executes
the full suite and enforces an encoded-size budget.

This phase is Workbench-owned and adds no parser algorithm or semantic
evaluator. Parser evidence continues to come from the research validation
programme, while Compiler remains the owner of semantic interpretation.
