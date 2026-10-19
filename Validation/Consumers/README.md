# Downstream compatibility fixtures

These packages compile Grammar Workbench strictly through its published products.

- `LibraryConsumer` exercises compilation, structural grammar analysis, bounded behavior comparison, structured, generalized, and adaptive platform parsing, stable forest identities, versioned UTF-16 edits, semantic reduction, project workspaces, source ranges, and semantic-model interchange.
- `CoreConsumer` exercises the portable core, graph interchange, and the public extension manifest, registry, context, and execution boundary from a separate package.
- `ReferenceExtension` publishes a reusable extension library and executes its deterministic capability-report command strictly through `GrammarWorkbenchCore`.
- `LSPConsumer` exercises the reusable language-server library product through its public document-store API.
- `PluginConsumer` exercises the SwiftPM build plugin and the dependency-free generated parser API.
- `SDKConsumer` exercises capability negotiation and the transport-neutral async client strictly through the language-tooling SDK product.

Run all six with `Scripts/validate-downstream.sh`. They intentionally live outside the root package target graph so accidental access to implementation-only declarations fails at compile time.
