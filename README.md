# Grammar Workbench

A native macOS SwiftUI foundation for inspecting generated LR parser artifacts.

## Run

```sh
swift run GrammarWorkbenchApp
```

The workbench ships with a self-contained expression grammar. Select SLR(1), LALR(1), or canonical LR(1) to construct its automaton and parsing table, click states or cells, inspect conflicts and precedence decisions, parse sample token streams with synchronized replay, and export the artifact as standalone HTML. Open a UTF-8 grammar file to inspect productions, diagnostics, nullable symbols, FIRST/FOLLOW sets, and its generated LR artifacts.

## Architecture

- `ArtifactModel.swift`: stable, typed identities and immutable artifact snapshots.
- `GrammarFrontEnd.swift`: source-located grammar parsing, diagnostics, and set analysis.
- `LRConstructionEngine.swift`: deterministic LR(0)/LR(1) closure, goto, LALR merging, table generation, and precedence resolution.
- `ParserRuntime.swift`: input tokenization, LR execution, parse trees, trace frames, conflict witnesses, and branch replay.
- `SampleArtifact.swift`: replaceable sample artifact provider.
- `ExplorerStore.swift`: cross-view selection and replay state.
- `ArtifactExplorerView.swift`: native master/detail explorer.
- `HTMLExporter.swift`: dependency-free standalone report export.

The UI consumes immutable `GrammarArtifact` values rather than construction internals, keeping artifact identities and inspection views independent from the algorithms that produce them.
