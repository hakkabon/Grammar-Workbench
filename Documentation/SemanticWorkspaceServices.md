# Semantic workspace services

Phase 11 turns the reducer-neutral incremental syntax index into language-aware project services without guessing a language's semantics. A `GrammarSemanticWorkspaceSchema` classifies terminal tokens by token kind and, optionally, an enclosing production identity. Each rule declares a symbol kind, whether the token is a definition or reference, and whether its scope is project-wide or document-local. Rules are evaluated in declaration order and the first match classifies the token.

Production identities come from `GrammarSemanticModel`, so schemas can resolve readable productions during setup instead of embedding unexplained numbers in application code:

```swift
let model = try GrammarSemanticModel(compilation: analysis.compilation)
let declaration = model.productions(
    lhs: "Statement", rhs: ["LET", "ID", "SEMI"]
).first!

let schema = GrammarSemanticWorkspaceSchema(rules: [
    .init(
        tokenKind: "ID", enclosingProduction: declaration.id,
        kind: "variable", role: .definition
    )
])
let services = analysis.semanticWorkspace(schema: schema)
```

The immutable, Codable `GrammarSemanticWorkspaceSnapshot` provides:

- searchable workspace definitions;
- occurrence lookup at a UTF-16 source offset;
- definition and reference resolution;
- unresolved, ambiguous, and duplicate-definition diagnostics;
- cross-document dependency edges with occurrence counts; and
- safe multi-document rename plans.

Rename validates the configured name pattern, requires one unambiguous definition, rejects collisions, groups edits by document, and records every expected revision. `GrammarProjectWorkspace.applySemanticRename` validates every document and text range before replacing the source set, preventing a stale multi-document plan from being partially applied.

Schemas and results are tool-neutral JSON contracts. Automation can inspect a project or produce a renamed project without modifying its input:

```sh
grammar-workbench project-semantic PROJECT SCHEMA [REPORT]
grammar-workbench project-rename PROJECT SCHEMA DOCUMENT UTF16_OFFSET NEW_NAME OUTPUT_PROJECT
```

`Examples/SemanticWorkspaceProject.json` and `Examples/SemanticWorkspaceSchema.json` form a runnable two-document definition/reference example.

The service is intentionally separate from application AST construction. `GrammarSemanticReducer` remains the typed evaluation boundary; workspace schemas provide the declarative naming layer needed by editors, language servers, project browsers, and refactoring tools.
