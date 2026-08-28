# Linux delivery

Grammar Workbench ships a headless Linux toolchain alongside the native macOS application. The Linux archive contains the command-line workbench, LSP server, stateful JSON-lines service, resource bundle, licenses, and a machine-readable platform manifest.

The SwiftUI application is intentionally not part of the Linux archive. Linux users work through an external editor connected to the LSP, direct CLI automation, the SDK/core Swift packages, or the long-lived service host.

## Requirements

- A 64-bit `x86_64` or `arm64` Linux system
- A glibc-based distribution compatible with the build environment
- Swift 6.3 when building from source; prebuilt archives do not require a Swift toolchain

The release archive is named `Grammar-Workbench-VERSION-linux-ARCH.tar.gz` and has an adjacent `.sha256` file. Verify and unpack it with:

```sh
sha256sum --check Grammar-Workbench-*-linux-*.tar.gz.sha256
tar -xzf Grammar-Workbench-*-linux-*.tar.gz
export PATH="$PWD/Grammar-Workbench-VERSION-linux-ARCH/bin:$PATH"
grammar-workbench platform-info
```

`platform-info` emits stable JSON describing the runtime OS, architecture, Workbench/API versions, included products, and graph-layout availability. Linux currently reports `interchangeOnly` for native layout: graph models, advanced geometry over precomputed layouts, DOT, SVG, and interchange remain portable, while the Swift-Layout binary backend remains a macOS integration.

## Editor and service integration

Launch the language server using the absolute executable path from the extracted `bin` directory:

```sh
grammar-workbench-lsp
```

The VS Code and Neovim configurations under `Clients/` can point to that executable. For persistent build or IDE processes, `grammar-workbench-service` accepts newline-delimited `GrammarToolingRequest` JSON and returns correlated responses as described in `StatefulToolingProtocol.md`.

## Containers

The repository Dockerfile builds all three Linux executables and uses the CLI as its entry point:

```sh
docker build -t grammar-workbench .
docker run --rm grammar-workbench platform-info
docker run --rm -v "$PWD:/workspace" grammar-workbench validate /workspace/MyLanguage.grammar
```

Override the entry point with `grammar-workbench-lsp` or `grammar-workbench-service` for an editor/tooling container.

## Producing and validating a release

On Linux:

```sh
Scripts/package-linux.sh
Scripts/validate-linux-delivery.sh
```

The validation gate builds the CLI, LSP, and service, runs portable API tests, packages the release, inspects its manifest, and runs the same CLI/LSP/service smoke suites used by macOS packaging. GitHub CI executes this gate on Ubuntu, and tagged releases produce a Linux archive independently of the macOS application artifacts.

The pinned Grammar revision predates portable logging support and imports Apple's
`OSLog` module directly. Portable build and packaging scripts run
`Scripts/prepare-portable-dependencies.sh`, which verifies that exact revision and
applies the narrow compatibility patch under `Patches/`. The workaround fails
closed if the dependency revision or source changes. It should be removed when a
Grammar release with conditional logging is available.
