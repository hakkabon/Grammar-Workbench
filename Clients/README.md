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

The preferred workflow places `.grammar-workbench-source.json` at the project
root. It declares the grammar path, language id, and rooted source globs. VS
Code and Neovim load this descriptor, attach the grammar automatically, and
send an explicit language-to-grammar URI mapping to the server. See
[`Documentation/SourceProjectsAndExternalEditors.md`](../Documentation/SourceProjectsAndExternalEditors.md).

The following basename convention remains available for projects without a
descriptor.

The server treats every document whose URI ends in `.grammarworkbench`,
`.grammar` (workbench notation) or `.ebnf` (ISO EBNF notation) as a grammar
document, and compiles it on open. Everything else is a source document, which
is parsed with the grammar whose file base name matches the document's
language id:

- `prog.grammarworkbench` provides the grammar for language id `prog`.
- `expr.ebnf` provides the grammar for language id `expr`.

Without a descriptor, both clients open grammar files with the language id
`grammarworkbench` (or `ebnf`), and source documents with the grammar base
name as the language id:

- **VS Code**: `grammarWorkbench.associations` maps file globs to grammar
  names, e.g. `{ "*.prog": "prog" }`.
- **Neovim**: `:set filetype=prog` on the source buffer, then
  `:GrammarWorkbench` (or add a `vim.filetype.add` mapping).

The server validates both kinds of documents and publishes diagnostics for
grammar compilation errors and lexical/syntax errors in source documents.
It advertises incremental text synchronization; changes use UTF-16 LSP ranges,
while full-document replacements remain supported for simpler clients.

## Other editors

Any JSON-RPC-over-stdio LSP client can attach to the server; only the language
id conventions above matter. Two minimal configurations for editors without a
dedicated client in this repository:

**Emacs (eglot)** — associate source files with the grammar base name:

```elisp
(add-to-list 'auto-mode-alist '("\\.prog\\'" . prog-mode))
(require 'eglot)
(add-hook 'prog-mode-hook 'eglot-ensure)
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '(prog-mode . ("grammar-workbench-lsp"))))
```

**Helix** — a `[language.server]` entry pointing at the binary:

```toml
[[language]]
name = "proto"
file-types = ["proto"]

[language.server]
command = "/path/to/grammar-workbench-lsp"
```

Both need `grammar-workbench-lsp` on `PATH` (or an absolute path). Clients that
do not implement the source-project descriptor must keep the grammar file (e.g.
`proto.grammarworkbench`) open in the same session.
