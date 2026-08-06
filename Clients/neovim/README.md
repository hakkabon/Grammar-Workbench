# Grammar Workbench — Neovim

Copy [`grammar-workbench.lua`](grammar-workbench.lua) to
`~/.config/nvim/after/plugin/grammar-workbench.lua` (or `luafile` it). The
config is a single `vim.lsp.start` (~30 lines) and needs Neovim 0.10+.

Build the server first:

```sh
swift build --product grammar-workbench-lsp   # → .build/debug/grammar-workbench-lsp
```

## Usage

- Grammar files (`.grammarworkbench`, `.grammar`, `.ebnf`) attach
  automatically; the server compiles them and reports grammar diagnostics.
- Source documents attach on demand. Set the buffer filetype to the grammar
  base name (e.g. `:set filetype=prog` for `prog.grammarworkbench`) and run:

  ```vim
  :GrammarWorkbench
  ```

- Add persistent source mappings in the config's `vim.filetype.add`, e.g.
  `pattern = { ["*.prog"] = "prog" }`.
- Override the binary with `let g:grammar_workbench_binary = "/path/to/grammar-workbench-lsp"`.

Completion (`<C-Space>`), hover (`K`), diagnostics, document symbols, and
folding come from the server's LSP capabilities.
