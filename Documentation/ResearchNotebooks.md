# Research notebooks

Phase 28 turns Grammar-REPL 0.9 experiment projects into durable Workbench
research narratives. Grammar-REPL still owns grammars, parser observations,
Compiler semantics, project capture, and replay verification. Workbench owns the
notebook: the question, ordered notes, evidence citations, and conclusions.

## Evidence boundary

A notebook records the project fingerprint and a canonical inventory of its
named experiments. An evidence cell refers to an experiment identifier and an
optional canonical engine selection. It does not copy a forest, reinterpret a
parse result, or claim that a recorded Grammar-REPL fingerprint has been
verified. Opening the original project resolves every reference and makes a
changed project or missing experiment visible.

Notebook schema 1 is path- and time-independent. Its FNV-1a fingerprint covers
the Workbench producer, title, research question, project inventory, and ordered
cells. Cell identifiers are unique; notes and conclusions cannot masquerade as
evidence; evidence can cite only engines recorded by its experiment.

## Native workflow

1. Open a Grammar-REPL experiment-project JSON document in **Experiments**.
2. Move between the named experiments and inspect their engine evidence.
3. Create a notebook and state the research question.
4. Add narrative notes, cite the current experiment, and record conclusions.
5. Save the notebook as JSON. Its evidence status remains resolved only while
   the open project has the exact recorded identity and experiment inventory.

## Headless workflow

```sh
grammar-workbench experiment-inspect study.json
grammar-workbench notebook-create study.json notebook.json \
  "Expression study" "Do the engines preserve the same ambiguity?"
grammar-workbench notebook-add notebook.json notebook-with-note.json note \
  context "Context" "Compare ambiguous and precedence-resolved inputs."
grammar-workbench notebook-add notebook-with-note.json final.json evidence \
  ambiguous "Ambiguous case" "Inspect the two derivations." ambiguous earley,rnglr
grammar-workbench notebook-inspect final.json study.json
```

`notebook-inspect` reports the notebook and project fingerprints, cell counts,
and resolution status. Parser replay remains the responsibility of
`grammar-repl-experiment verify`.

The public format is documented by
`Validation/Research/ResearchNotebook.schema.json`.
