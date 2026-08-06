# Grammar Workbench — VS Code extension

A minimal, dependency-free LSP client for the `grammar-workbench-lsp` server.
It spawns the server and provides diagnostics, completion, hover, document
symbols, and folding for grammar and source documents.

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
diagnostics, completion, hover, symbols, and folding all work against the
workspace's own `.build/debug/grammar-workbench-lsp` binary.

## Package

Build a shareable `.vsix` (requires Node.js):

```sh
cd Clients/vscode
npx --yes @vscode/vsce package --allow-missing-repository
code --install-extension grammar-workbench-lsp-0.1.0.vsix
```

The produced VSIX is also shipped alongside the server binary by
`Scripts/package-release.sh` (see `dist/`).

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
diagnostics appear as you type, and completion (expected terminals with fuzzy
matching), hover (token + grammar production), document symbols, and folding
work in both document kinds.

## Develop

```sh
code --extensionDevelopmentPath ./Clients/vscode
```

The protocol handling is verified end to end (with a stubbed `vscode`) by:

```sh
node Scripts/m4-client-test.js
```
