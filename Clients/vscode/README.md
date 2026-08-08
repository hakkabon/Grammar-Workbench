# Grammar Workbench — VS Code extension

A minimal, dependency-free LSP client for the `grammar-workbench-lsp` server.
It spawns the server and provides diagnostics, completion, hover, definitions,
<<<<<<< HEAD
references, rename, quick fixes, semantic tokens, document symbols, document
highlights, formatting, document links, and folding for grammar and source
documents.
=======
quick fixes, document symbols, and folding for grammar and source documents.
>>>>>>> dev-branch

## Install

1. Build the server:

   ```sh
   swift build --product grammar-workbench-lsp
   ```

2. Install the extension from the workspace root (or copy this folder into
   `~/.vscode/extensions/grammar-workbench-lsp-0.1.0/`):

   ```sh
   code --install-extension ./Clients/vscode
   ```

A ready-made demo workspace lives in `Examples/lsp` (repository root): open the
repository in VS Code, then open `Examples/lsp/sample.proto` — the
<<<<<<< HEAD
diagnostics, completion, hover, symbols, folding, semantic highlighting,
references, rename, quick fixes, document highlights, formatting, and document
links all work against the workspace's own
`.build/debug/grammar-workbench-lsp` binary.
=======
diagnostics, completion, hover, symbols, and folding all work against the
workspace's own `.build/debug/grammar-workbench-lsp` binary.
>>>>>>> dev-branch

## Package

Build a shareable `.vsix` (requires Node.js):

```sh
cd Clients/vscode
npx --yes @vscode/vsce package --allow-missing-repository
code --install-extension grammar-workbench-lsp-0.1.0.vsix
```

<<<<<<< HEAD
The produced VSIX is also shipped alongside the server binary by
`Scripts/package-release.sh` (see `dist/`).
=======
Release archives include this dependency-free client source. A VSIX remains an
explicit packaging step so release validation never downloads npm tooling.
>>>>>>> dev-branch

## Configure

- `grammarWorkbench.serverPath` — path to the server binary; the default is
  `${workspaceFolder}/.build/debug/grammar-workbench-lsp`. Set it to a release
  build or an absolute path when needed.
- `grammarWorkbench.associations` — maps file globs to grammar names. A source
  document matching a glob is analyzed with the grammar of that name:

  ```json
  {
    "grammarWorkbench.associations": {
      "*.prog": "prog"
    }
  }
  ```

  `prog.grammarworkbench` must be open in the workspace for `*.prog` files to
  be analyzed.

## Usage

Open any `.grammarworkbench`, `.grammar`, or `.ebnf` file: the server compiles
it and reports grammar errors. Open a source file matching an association:
<<<<<<< HEAD
diagnostics appear as you type, and completion (expected terminals with fuzzy
matching), hover (token + grammar production), go-to-definition, document
symbols, document highlights, formatting, document links, and folding work in
both document kinds.

Grammar documents additionally get semantic highlighting (directives,
terminals, symbols, patterns), references and rename for nonterminals and
token names, and quick fixes that declare undefined symbols, insert missing
punctuation, and replace unknown directives. Source documents get quick fixes
that insert or delete the tokens the parser recovered, plus document
highlights for repeated tokens and links that jump from a token to the rule
that defines it in the grammar.
=======
diagnostics appear as you type. Grammar documents additionally provide shared
editor completion, go-to-definition, and quick fixes; source documents provide
expected-terminal completion, production-aware hover, document symbols, and folding.
>>>>>>> dev-branch

## Develop

```sh
code --extensionDevelopmentPath ./Clients/vscode
```

The protocol handling is verified end to end (with a stubbed `vscode`) by:

```sh
node Scripts/m4-client-test.js
```
