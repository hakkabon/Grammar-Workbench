# Grammar Workbench clients

Two minimal LSP clients for the `grammar-workbench-lsp` server, which speaks
JSON-RPC over stdio:

- [`vscode/`](vscode/README.md) — a dependency-free VS Code extension
  (diagnostics, completion, hover, document symbols, folding).
- [`neovim/`](neovim/README.md) — a ~30-line `vim.lsp.start` configuration.

## Building the server

```sh
swift build --product grammar-workbench-lsp
# → .build/debug/grammar-workbench-lsp
```

## How documents are associated with grammars

The server treats every document whose URI ends in `.grammarworkbench`,
`.grammar` (workbench notation) or `.ebnf` (ISO EBNF notation) as a grammar
document, and compiles it on open. Everything else is a source document, which
is parsed with the grammar whose file base name matches the document's
language id:

- `prog.grammarworkbench` provides the grammar for language id `prog`.
- `expr.ebnf` provides the grammar for language id `expr`.

Both clients therefore open grammar files with the language id
`grammarworkbench` (or `ebnf`), and source documents with the grammar base
name as the language id:

- **VS Code**: `grammarWorkbench.associations` maps file globs to grammar
  names, e.g. `{ "*.prog": "prog" }`.
- **Neovim**: `:set filetype=prog` on the source buffer, then
  `:GrammarWorkbench` (or add a `vim.filetype.add` mapping).

The server validates both kinds of documents and publishes diagnostics for
grammar compilation errors and lexical/syntax errors in source documents.
