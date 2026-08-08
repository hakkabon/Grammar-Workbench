# Downstream compatibility fixtures

These packages compile Grammar Workbench strictly through its published products.

- `LibraryConsumer` exercises compilation, structured parsing, semantic reduction, source ranges, and semantic-model interchange.
- `PluginConsumer` exercises the SwiftPM build plugin and the dependency-free generated parser API.

Run both with `Scripts/validate-downstream.sh`. They intentionally live outside the root package target graph so accidental access to implementation-only declarations fails at compile time.
