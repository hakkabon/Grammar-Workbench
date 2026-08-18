# Source projects and external-editor workflow

Phase 22 connects ordinary program files to one Grammar Workbench grammar
without relying on matching filenames. A source project is described by
`.grammar-workbench-source.json`, a versioned filesystem-facing contract shared
by the native application, CLI, VS Code, Neovim, and LSP initialization.

```json
{
  "schemaVersion": 1,
  "kind": "grammar-workbench-source-project",
  "apiVersion": 1,
  "name": "Expression source project",
  "grammar": {
    "path": "Expression.grammar",
    "notation": "Workbench",
    "algorithm": "LALR(1)",
    "languageID": "expression"
  },
  "associations": [
    { "pattern": "Sources/**/*.expr", "languageID": "expression" }
  ]
}
```

Grammar and optional semantic-schema paths must be safe relative paths. Source
patterns support `*`, `**`, and `?`; matching is rooted at the descriptor's
directory. Loading skips hidden files and packages, rejects non-UTF-8 input,
bounds individual file size and total file count, and converts the resolved
snapshot into the existing embedded `GrammarProjectManifest`. Analysis then
uses `GrammarProjectWorkspace`, not a GUI-specific parser path.

## Native Workbench

Choose **Open Source Project** and select the descriptor. The Workbench loads
the declared grammar, analyzes every matched program through the shared
incremental coordinator, and opens the Project workspace. Associated files show
accepted/error status and a selectable source preview. Grammar, lexical, syntax,
test, and optional semantic problems use the integrated project problem model;
selecting a source problem selects the corresponding file.

Source previews are intentionally read-only in this milestone. External
editors remain authoritative for ordinary program files; reopening the
descriptor refreshes the filesystem snapshot. The grammar remains editable in
the native grammar editor.

## VS Code and Neovim

The VS Code client discovers `.grammar-workbench-source.json` in the first
workspace folder, merges its rooted associations with explicit settings, opens
the declared grammar in the LSP session, and sends the language-to-grammar URI
map in LSP initialization options. Commands open either the associated grammar
or descriptor. `grammarWorkbench.projectFile` selects a different descriptor.

The Neovim client discovers the same conventional file at the workspace root,
assigns matching source filetypes, supplies initialization associations, and
loads and attaches the grammar buffer automatically.

The LSP retains basename matching for clients without descriptor support, but
an explicit initialized association takes priority. Completion, hover,
definitions, document links, diagnostics, incremental edits, and syntax-tree
services consequently use the configured grammar even when its filename and
language identifier differ.

## Automation

```sh
grammar-workbench source-project-check .grammar-workbench-source.json
grammar-workbench source-project-export .grammar-workbench-source.json Project.json
```

`source-project-check` resolves and analyzes the current filesystem snapshot,
including optional workspace semantics. `source-project-export` creates a
portable embedded manifest suitable for CI, SDK transport, or archival
reproduction. This keeps filesystem authority at host boundaries while the SDK
continues to exchange deterministic self-contained projects.
