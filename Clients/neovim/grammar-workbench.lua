-- Grammar Workbench LSP client (~30 lines). Copy to
-- ~/.config/nvim/after/plugin/grammar-workbench.lua, or `luafile` it.
-- Build the server first: swift build --product grammar-workbench-lsp
-- Override the binary with: let g:grammar_workbench_binary = "/path/to/grammar-workbench-lsp"
local binary = vim.g.grammar_workbench_binary or vim.fn.getcwd() .. "/.build/debug/grammar-workbench-lsp"
local root = vim.fs.root(0, { ".grammar-workbench-source.json", ".git" }) or vim.fn.getcwd()
local descriptor_path = root .. "/.grammar-workbench-source.json"
local descriptor = nil
if vim.fn.filereadable(descriptor_path) == 1 then
  local ok, value = pcall(vim.json.decode, table.concat(vim.fn.readfile(descriptor_path), "\n"))
  if ok and value.kind == "grammar-workbench-source-project" then descriptor = value end
end

vim.filetype.add({
  extension = { grammarworkbench = "grammarworkbench", grammar = "grammarworkbench", ebnf = "ebnf" },
  -- Source documents: add your own mappings here; the filetype must equal the
  -- grammar base name, e.g. pattern = { ["*.prog"] = "prog" } for prog.grammarworkbench
})

local on_attach = function(_, bufnr)
  vim.keymap.set("n", "K", vim.lsp.buf.hover, { buffer = bufnr })
  vim.keymap.set("i", "<C-Space>", vim.lsp.completion.trigger, { buffer = bufnr })
end

local source_filetypes = {}
if descriptor then
  for _, association in ipairs(descriptor.associations or {}) do
    source_filetypes[association.languageID] = true
  end
  vim.api.nvim_create_autocmd("BufReadPost", {
    pattern = "*",
    callback = function(args)
      local relative = vim.fs.relpath(root, vim.api.nvim_buf_get_name(args.buf))
      if not relative then return end
      for _, association in ipairs(descriptor.associations or {}) do
        if vim.fn.match(relative, vim.fn.glob2regpat(association.pattern)) >= 0 then
          vim.bo[args.buf].filetype = association.languageID
          return
        end
      end
    end,
  })
end

local function start()
  local found = vim.lsp.get_clients({ name = "grammar-workbench" })[1]
  if found then return found.id end
  local filetypes = { "grammarworkbench", "ebnf" }
  for language_id, _ in pairs(source_filetypes) do table.insert(filetypes, language_id) end
  local grammar_associations = {}
  if descriptor then
    grammar_associations[descriptor.grammar.languageID] = vim.uri_from_fname(root .. "/" .. descriptor.grammar.path)
  end
  local id = vim.lsp.start({
    name = "grammar-workbench",
    cmd = { binary },
    filetypes = filetypes,
    root_dir = root,
    init_options = { grammarWorkbench = { grammarAssociations = grammar_associations } },
    on_attach = on_attach,
  })
  if descriptor and id then
    local grammar_buffer = vim.fn.bufadd(root .. "/" .. descriptor.grammar.path)
    vim.fn.bufload(grammar_buffer)
    vim.lsp.buf_attach_client(grammar_buffer, id)
  end
  return id
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = vim.list_extend({ "grammarworkbench", "ebnf" }, vim.tbl_keys(source_filetypes)),
  callback = function() vim.lsp.buf_attach_client(0, start()) end,
})

-- Source documents: :GrammarWorkbench attaches the client to the current
-- buffer (set the filetype to the grammar base name, e.g. :set filetype=prog).
vim.api.nvim_create_user_command("GrammarWorkbench", function()
  vim.lsp.buf_attach_client(0, start())
end, { desc = "Attach the Grammar Workbench LSP client to this buffer" })
