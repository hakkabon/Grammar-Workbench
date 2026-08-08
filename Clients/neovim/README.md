# Grammar Workbench — Neovim

Copy [`grammar-workbench.lua`](grammar-workbench.lua) to
`~/.config/nvim/after/plugin/grammar-workbench.lua` (or `luafile` it). The
config is a single `vim.lsp.start` (~30 lines) and needs Neovim 0.10+.

Build the server first:

```sh
swift build --product grammar-workbench-lsp   # → .build/debug/grammar-workbench-lsp
```

## Verify

With Neovim 0.10+ and the config installed, open
`Examples/lsp/proto.grammarworkbench` in a terminal (`nvim` from the
repository root): grammar diagnostics appear on invalid edits, folding and
document symbols work. Then open `Examples/lsp/sample.proto`, run
`:set filetype=proto` followed by `:GrammarWorkbench`, and check the LSP
diagnostic (line 2 is missing its expression): `:lua vim.diagnostic.open_float()`.

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
