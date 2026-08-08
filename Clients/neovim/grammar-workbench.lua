-- Grammar Workbench LSP client (~30 lines). Copy to
-- ~/.config/nvim/after/plugin/grammar-workbench.lua, or `luafile` it.
-- Build the server first: swift build --product grammar-workbench-lsp
-- Override the binary with: let g:grammar_workbench_binary = "/path/to/grammar-workbench-lsp"
local binary = vim.g.grammar_workbench_binary or vim.fn.getcwd() .. "/.build/debug/grammar-workbench-lsp"

vim.filetype.add({
  extension = { grammarworkbench = "grammarworkbench", grammar = "grammarworkbench", ebnf = "ebnf" },
  -- Source documents: add your own mappings here; the filetype must equal the
  -- grammar base name, e.g. pattern = { ["*.prog"] = "prog" } for prog.grammarworkbench
})

local on_attach = function(_, bufnr)
  vim.keymap.set("n", "K", vim.lsp.buf.hover, { buffer = bufnr })
  vim.keymap.set("i", "<C-Space>", vim.lsp.completion.trigger, { buffer = bufnr })
end

local function start()
  local found = vim.lsp.get_clients({ name = "grammar-workbench" })[1]
  if found then return found.id end
  return vim.lsp.start({
    name = "grammar-workbench",
    cmd = { binary },
    filetypes = { "grammarworkbench", "ebnf" },
    root_dir = vim.fs.root(0, ".git") or vim.fn.getcwd(),
    on_attach = on_attach,
  })
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "grammarworkbench", "ebnf" },
  callback = function() vim.lsp.buf_attach_client(0, start()) end,
})

-- Source documents: :GrammarWorkbench attaches the client to the current
-- buffer (set the filetype to the grammar base name, e.g. :set filetype=prog).
vim.api.nvim_create_user_command("GrammarWorkbench", function()
  vim.lsp.buf_attach_client(0, start())
end, { desc = "Attach the Grammar Workbench LSP client to this buffer" })
