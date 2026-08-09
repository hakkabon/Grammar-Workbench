# Ecosystem expansion

Grammar Workbench exposes the same compilation and editor behavior through several independently consumable surfaces.

## SwiftPM products

- `GrammarWorkbench` is the stable parser, semantic, generator, and interchange library.
- `GrammarWorkbenchPlugin` generates standalone parsers during a SwiftPM build.
- `GrammarWorkbenchLSP` embeds the language server in another Swift process or test harness.
- `grammar-workbench`, `grammar-workbench-lsp`, and `GrammarWorkbenchApp` are the CLI, stdio server, and native application.

The LSP protocol and transport implementation is vendored from the Swift project because the upstream package requires a newer toolchain. It is isolated behind the LSP product and can be replaced with the upstream dependency without changing Grammar Workbench APIs.

## Editor clients

The dependency-free VS Code extension implements JSON-RPC framing directly with Node built-ins. The Neovim client is a small `vim.lsp.start` configuration. Emacs, Helix, and other LSP clients can launch the same stdio executable without a custom adapter.

A grammar file is associated with source documents through its base name. For example, `proto.grammarworkbench` supplies language id `proto`; clients map source extensions to that id. Multiple grammars may be open concurrently, and exact language-id matching is required for completion and hover so tooling never guesses with the wrong grammar.

## Supported services

Grammar documents provide compilation diagnostics, Workbench/EBNF-aware completion, definition navigation, and quick fixes shared with the native editor. Source documents provide lexical and recovery diagnostics, expected-token completion, production-aware hover, hierarchical symbols, and folding. Open/change/save/close synchronization republishes affected source diagnostics when a grammar changes.

## Project automation

Portable project manifests group a grammar, multiple source snapshots, regression tests, and generator targets behind the same public library contracts. `GrammarProjectWorkspace` supplies aggregate analysis and indexing to IDEs and build services, while the CLI provides `project-check` and `project-generate` for CI. Manifests embed their inputs and restrict output declarations to safe relative paths, making validation deterministic and preventing generator configuration from escaping its chosen output root.

## Validation and distribution

The release-candidate gate runs the complete Swift suite, a framed stdio smoke session, and—when Node is available—the real VS Code client against the server. Release packaging produces independent LSP and editor-client archives, includes them in `SHA256SUMS`, and does not download npm dependencies. Consumers may package the included VS Code source as a VSIX explicitly with `@vscode/vsce`.
