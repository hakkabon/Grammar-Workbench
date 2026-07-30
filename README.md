# Grammar Workbench

A native macOS SwiftUI foundation for inspecting generated LR parser artifacts.

## Run

```sh
swift run GrammarWorkbench
```

The initial milestone ships with a self-contained expression-grammar artifact. Select an LR algorithm, click automaton states or parsing-table cells, inspect decisions and conflicts, replay witness branches, follow a sample parse trace, and export the current artifact as standalone HTML.

## Architecture

- `ArtifactModel.swift`: stable, typed identities and immutable artifact snapshots.
- `SampleArtifact.swift`: replaceable sample artifact provider.
- `ExplorerStore.swift`: cross-view selection and replay state.
- `ArtifactExplorerView.swift`: native master/detail explorer.
- `HTMLExporter.swift`: dependency-free standalone report export.

The UI consumes `GrammarArtifact` values rather than generator internals, allowing a future grammar/parser service to publish snapshots without changing inspection views.
