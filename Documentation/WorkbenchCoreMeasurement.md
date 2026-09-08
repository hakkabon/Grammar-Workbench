# WorkbenchCore pre-split measurement

`GrammarWorkbenchCore` currently re-exports and depends on the complete
`GrammarWorkbench` target. Before changing that physical ownership, the
repository records a reproducible structural baseline in
`Validation/CoreSeparation/Baseline.json`.

The reviewed plan classifies every implementation source as:

- **portable** — a direct candidate for physical Core ownership and free of
  imports from the reviewed native-framework set;
- **native** — an application or presentation source that remains outside the
  physical Core target; or
- **mixed** — a file that must first separate portable declarations from native
  presentation declarations.

The baseline measures files, bytes, physical and nonblank lines, public
declaration occurrences, conditional-compilation directives, imports, resource
size, and the current façade relationship. A digest covers the detailed
per-source observations. These structural values are deterministic and form the
before/after comparison for a future split.

Run the gate locally:

```sh
node Scripts/measure-workbench-core.mjs --check
```

Generate a detailed report without changing the baseline:

```sh
node Scripts/measure-workbench-core.mjs \
  --report .build/core-separation-report.json
```

To add a machine-specific build observation, use the same scratch directory,
job count, Swift toolchain, and hardware before and after the split:

```sh
node Scripts/measure-workbench-core.mjs --build --jobs 2 \
  --scratch-path .build/core-separation-measurement \
  --report .build/core-separation-build.json
```

Build duration is intentionally excluded from the checked baseline because it
is hardware-, cache-, and toolchain-sensitive. The generated report records
those comparison inputs alongside the duration.

## Current result

The pre-split implementation contains 66 files and 21,924 lines. Fifty-four
files, representing 77.2% of the lines, are already portable candidates. Nine
files are native-only. Three files form the extraction queue:

1. `GrammarEditor.swift`
2. `GrammarWorkbenchDocument.swift`
3. `ProductionSupport.swift`

A future split should first empty that mixed queue, then move the reviewed
portable set behind `GrammarWorkbenchCore`, and finally repeat the structural
and controlled build measurements. A baseline update is a reviewed architecture
change: inspect the detailed report and update the plan and baseline together.
