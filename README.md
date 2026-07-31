# Grammar Workbench

A native macOS SwiftUI foundation for inspecting generated LR parser artifacts.

## Run

```sh
swift run GrammarWorkbenchApp
```

The app is a native document-based workbench. `.grammarworkbench` documents persist editable grammar source, the selected LR algorithm, and named sample inputs with macOS autosave and undo support. Plain-text grammars can also be opened and exported. Edits regenerate diagnostics and artifacts after a short debounce while retaining the last valid automaton during syntax errors.

The native grammar editor provides syntax highlighting, line numbers, Find, symbol/directive completion, inline diagnostic underlines, source navigation from artifacts and diagnostics, semantic grammar warnings, and targeted quick fixes.

Use `%token NAME ...` to enable explicit-terminal mode and undefined-symbol validation. Grammars without `%token` remain compatible and infer unquoted terminals.

## Architecture

- `ArtifactModel.swift`: stable, typed identities and immutable artifact snapshots.
- `GrammarFrontEnd.swift`: source-located grammar parsing, diagnostics, and set analysis.
- `LRConstructionEngine.swift`: deterministic LR(0)/LR(1) closure, goto, LALR merging, table generation, and precedence resolution.
- `ParserRuntime.swift`: input tokenization, LR execution, parse trees, trace frames, conflict witnesses, and branch replay.
- `GrammarWorkbenchDocument.swift`: native document persistence and the public document-hosting view.
- `GrammarEditor.swift`: native AppKit-backed editor, source decoration, completion, line numbering, and quick fixes.
- `SampleArtifact.swift`: replaceable sample artifact provider.
- `ExplorerStore.swift`: cross-view selection and replay state.
- `ArtifactExplorerView.swift`: native master/detail explorer.
- `HTMLExporter.swift`: dependency-free standalone report export.

The UI consumes immutable `GrammarArtifact` values rather than construction internals, keeping artifact identities and inspection views independent from the algorithms that produce them.
