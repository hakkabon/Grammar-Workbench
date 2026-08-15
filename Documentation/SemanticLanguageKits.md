# Semantic language kits

Phase 15 packages the language-specific decisions that previously lived in separate host files. A `GrammarSemanticLanguageKitManifest` binds a grammar, semantic workspace schema, filename extensions, conformance tests, generator defaults, identity, and version into one portable JSON contract.

## Validation

`GrammarSemanticLanguageKit.compile` validates the envelope and compiles the grammar before accepting the kit. It rejects:

- incompatible schema or Grammar Workbench API versions;
- unsafe identifiers, extensions, and generator paths;
- semantic rules that name missing terminals or production identities;
- duplicate selectors that can never be reached because rules are ordered; and
- failing conformance tests, unless inspection mode is explicitly requested.

This makes stale production IDs visible when a grammar changes instead of silently degrading navigation and refactoring.

```swift
let kit = try GrammarSemanticLanguageKitCodec.decode(data, requirePassingTests: true)
let result = try await kit.analyze(
    name: "My project",
    sources: [.init(id: "main", path: "Sources/main.tiny", text: "let value;")]
)
let symbols = result.semantics.workspaceSymbols()
```

The compiled kit retains its grammar compilation and semantic model. It can create multiple `GrammarProjectWorkspace` instances without requiring consumers to reconstruct the language definition or semantic schema.

## Tooling and service hosts

The SDK exposes `languageKitValidate` and `languageKitAnalyze`. Their JSON envelopes carry the manifest in `languageKit`; analysis also accepts a project envelope as the source container. A stateful `sessionOpen` request may supply a kit instead of a compilation request. The resulting session reports `languageKitIdentifier`, preserving provenance while using the same incremental document lifecycle introduced in Phase 14.

The command line offers:

```sh
grammar-workbench kit-validate Examples/TinySemanticLanguageKit.json
grammar-workbench kit-project Examples/TinySemanticLanguageKit.json Project.json
```

The first command performs strict validation and conformance testing. The second creates a portable empty project initialized with the kit’s grammar, tests, and generator defaults.

## Contract boundary

Kits describe portable syntax and workspace semantics; application-specific typed AST values remain Swift code implemented with `GrammarSemanticReducer`. This keeps kit files safe and language-neutral while allowing native consumers to layer strongly typed evaluation on the validated semantic model.
