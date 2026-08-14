# Project and ecosystem infrastructure

`GrammarProjectManifest` is the portable boundary for a complete language project. Unlike the native single-document format, a project manifest combines one grammar configuration with multiple embedded source documents, batch tests, and named generator targets. Embedded source text makes the same manifest reproducible in editors, CI, and build daemons without giving the library authority over a host filesystem.

## Compatibility and validation

Project JSON uses the `grammar-workbench-project` kind, its own schema version, and the public Grammar Workbench API version. `GrammarProjectCodec` rejects future schemas, incompatible APIs, incorrect envelope kinds, empty project names, duplicate source identities or paths, duplicate target identities, and unsafe relative paths. Paths cannot be absolute, contain traversal components, backslashes, empty components, or NUL bytes.

The original `GrammarWorkbenchInterchange` remains the native app's single-document exchange format. Its schema-1 and schema-2 compatibility behavior is unchanged. Project manifests are a separate envelope so ecosystem growth does not silently alter existing documents.

## Project workspace

`GrammarProjectWorkspace` compiles the manifest grammar once and owns a shared incremental analysis coordinator for every declared source. `analyze()` returns source snapshots in manifest order, one combined semantic index, and the batch-test report. Ranged edits reuse the same lexing, deterministic parsing, semantic-indexing, and identity infrastructure used by the native app and LSP.

Grammar replacement atomically installs a new successful compilation and refreshes every source. A failed replacement leaves the previous workspace usable. `GrammarProjectAnalysis.isSuccessful` requires a valid compilation, a snapshot for every declared source, clean accepted parses, and either no tests or an entirely passing test suite.

`replaceSources` reconciles project membership while retaining incremental state for matching document identities and releasing removed documents. Tests and generator plans can be replaced independently after the same manifest validation, allowing long-lived editor and daemon workspaces to evolve without reconstruction.

`parse(documentID:options:)` and `parseAll(options:batchOptions:)` expose the advanced parsing platform over manifest sources. Project-wide batches preserve manifest order and enforce their declared concurrency bound independently of incremental deterministic analysis.

`structuralGrammarAnalysis()` exposes the grammar analysis library for the project grammar. `previewGrammarTransformation` validates a cleanup plan against every embedded project source, the bounded generated corpus, and the manifest's saved tests without mutating the workspace.

The project index preserves document identity and manifest path around each `GrammarIncrementalIndexEntry`. It supports project-wide symbol lookup and per-document filtering without conflating session-local syntax identities across documents.

`GrammarProjectAnalysis.semanticWorkspace(schema:)` adds a declarative language-aware layer over that index. Token kinds and enclosing production identities classify definitions and references, from which the service derives workspace symbols, navigation, diagnostics, dependency edges, and revision-guarded rename plans. `GrammarProjectWorkspace.applySemanticRename` validates all affected revisions and ranges before changing any source. See [SemanticWorkspaceServices.md](SemanticWorkspaceServices.md).

## Generators and automation

Generator targets name a registry identifier, a safe relative output directory, and versioned string options. `GrammarProjectWorkspace.generate(using:)` validates and invokes them through the normal `GrammarGeneratorRegistry`; applications can supply a registry containing custom generators.

The CLI exposes the same workflow:

```sh
grammar-workbench project-check Examples/ExpressionProject.json
grammar-workbench project-generate Examples/ExpressionProject.json .build/generated
grammar-workbench project-semantic Project.json SemanticSchema.json Report.json
```

`project-check` compiles the grammar, analyzes every source, runs tests, validates all generator targets, and returns a failing exit status if project analysis fails. `project-generate` requires successful analysis and writes each validated generated filename beneath its declared output directory. `Examples/ExpressionProject.json` is the release-tested reference manifest.
