# Ecosystem expansion

Semantic language kits are the portable distribution unit for language-specific configuration. They can be validated in-process or through `languageKitValidate`, analyzed through `languageKitAnalyze`, and supplied directly to `sessionOpen`. This keeps editor, CI, and service-host consumers on one grammar and semantic contract.

Graph layout is consumed through the independently released Swift-Layout package. Tagged Layout releases build the XCFramework and generated Swift bindings, publish the binary, and update Swift-Layout automatically. Grammar Workbench pins a tested Swift-Layout revision and exposes only its own portable graph contracts to downstream consumers.

Canonical grammar interchange is independent of parser-table artifacts and document persistence. BNF-profile, Workbench, and EBNF sources normalize into fingerprinted `GrammarPortableInterchange` envelopes; bootstrap bundles add fixed-point and differential-validation evidence for research and CI consumers.

Research programmes package falsifiable parser hypotheses and bounded corpora for local runs, CI, SDK hosts, and cross-version baseline comparison. Deterministic evidence fingerprints remain separate from hardware-sensitive timing summaries.

Grammar Workbench exposes the same compilation and editor behavior through several independently consumable surfaces.

## SwiftPM products

- `GrammarWorkbenchCore` is the platform-neutral façade for parser, semantic, project, generator, and interchange services.
- `GrammarWorkbench` is the stable parser, semantic, generator, and interchange library.
- `GrammarWorkbenchSDK` is the versioned, transport-neutral language-tooling client and service boundary.
- `GrammarWorkbenchPlugin` generates standalone parsers during a SwiftPM build.
- `GrammarWorkbenchLSP` embeds the language server in another Swift process or test harness.
- `grammar-workbench`, `grammar-workbench-lsp`, and `GrammarWorkbenchApp` are the CLI, stdio server, and native application.
- `grammar-workbench-service` is the persistent JSON-lines host for stateful SDK sessions.

The LSP protocol and transport implementation is vendored from the Swift project because the upstream package requires a newer toolchain. It is isolated behind the LSP product and can be replaced with the upstream dependency without changing Grammar Workbench APIs.

Native SwiftUI, AppKit, and WebKit declarations are compile-time isolated from the core surface. See [CrossPlatformCoreSeparation.md](CrossPlatformCoreSeparation.md) for the portability contract and graph-backend behavior.

## Editor clients

The dependency-free VS Code extension implements JSON-RPC framing directly with Node built-ins. The Neovim client is a small `vim.lsp.start` configuration. Emacs, Helix, and other LSP clients can launch the same stdio executable without a custom adapter.

A grammar file is associated with source documents through its base name. For example, `proto.grammarworkbench` supplies language id `proto`; clients map source extensions to that id. Multiple grammars may be open concurrently, and exact language-id matching is required for completion and hover so tooling never guesses with the wrong grammar.

## Supported services

Grammar documents provide compilation diagnostics, Workbench/EBNF-aware completion, definition navigation, and quick fixes shared with the native editor. Source documents provide lexical and recovery diagnostics, expected-token completion, production-aware hover, hierarchical symbols, and folding. Open/change/save/close synchronization republishes affected source diagnostics when a grammar changes.

## Project automation

Portable project manifests group a grammar, multiple source snapshots, regression tests, and generator targets behind the same public library contracts. `GrammarProjectWorkspace` supplies aggregate analysis and indexing to IDEs and build services, while the CLI provides `project-check` and `project-generate` for CI. Manifests embed their inputs and restrict output declarations to safe relative paths, making validation deterministic and preventing generator configuration from escaping its chosen output root.

The advanced parsing platform is available from the library, project workspaces, and `platform-parse` CLI command. These surfaces share the same engine-selection, ambiguity, cancellation, and resource-limit semantics, so CI results can be reproduced in an editor or embedded service.

Structural grammar reports and explainable transformations are similarly shared by the library, Guide workspace, project workspaces, and CLI. Behavioral comparison uses the generalized recognizer so ambiguity does not masquerade as a language difference, while exact bounds and concrete counterexamples remain visible to automation.

## Portable tooling hosts

Swift hosts can embed `GrammarLanguageToolingService`; other runtimes can exchange
the same JSON envelopes through `grammar-workbench tooling-request`. Capability
negotiation exposes supported operations and schemas without coupling clients to
a release. See [LanguageToolingSDK.md](LanguageToolingSDK.md).

Clients that retain documents use `GrammarStatefulLanguageToolingService` or the
JSON-lines host. Per-session operations are serialized, independent sessions run
concurrently, and cancellation targets public request identifiers.

## Validation and distribution

The release-candidate gate runs the complete Swift suite, a framed stdio smoke session, and—when Node is available—the real VS Code client against the server. Release packaging produces independent LSP and editor-client archives, includes them in `SHA256SUMS`, and does not download npm dependencies. Consumers may package the included VS Code source as a VSIX explicitly with `@vscode/vsce`.
