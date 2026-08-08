# Semantic developer experience

Grammar Workbench separates deterministic parsing from application semantics. The parser produces a source-aware concrete syntax tree; a semantic reducer converts that tree into an AST, evaluator result, symbol index, or another `Sendable` value.

## Start from generated actions

Generate a compiling Swift starter with one closure for every production:

```sh
grammar-workbench generate semantic-swift Language.grammar Generated typeName=LanguageSemantics
```

The generated `LanguageSemantics.make()` returns `GrammarSemanticActions<String>`. Change `String` to the application value type, adjust the terminal and recovery behavior, and replace each default fold with the corresponding AST construction. Production comments show both the parser identity and readable rule.

The generated file belongs to the application and is safe to edit. Regeneration is intended as a reviewable way to discover grammar changes, not as a build-time overwrite of handwritten semantics.

## Validate before parsing

```swift
let compilation = GrammarWorkbenchAPI.compile(.init(source: source))
let semantics = try LanguageSemantics.make()
try GrammarSemanticModel(compilation: compilation).validate(semantics)
let result = try compilation.parse(input, using: semantics)
```

Validation reports every grammar production without a handler and every registered ID no longer present in the grammar. Duplicate handlers fail when the action set is constructed. This makes semantic drift visible in tests even when sample inputs do not exercise every production.

Use `production(id:)` for syntax-tree identities and `productions(lhs:rhs:)` when tests or integration code need to resolve a readable rule. Numeric IDs remain scoped to a compiled grammar and should not be persisted across grammar edits.

## Choose the appropriate reducer style

- Use `GrammarSemanticActions` for concise AST builders and evaluators with explicit coverage.
- Implement `GrammarSemanticReducer` directly when semantics require shared services, richer state, or a dedicated domain abstraction.
- Use `semantic-model-json` when reducer generation happens in another process or language.

Terminal handlers receive the complete token snapshot and syntax node, including lexeme, lexer mode, and source range. Missing-token handlers define the semantic behavior of accepted parses that used recovery. Production handlers receive `GrammarSemanticReduction`, which groups the production, already-evaluated children, and the source-aware reduction node.
