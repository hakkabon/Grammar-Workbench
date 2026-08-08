# Vendored Language Server Protocol framework

This directory contains vendored source for the Swift LSP framework used by the
`grammar-workbench-lsp` server. The code is **not** part of Grammar Workbench
itself; it is the official Swift language-server protocol implementation, vendored
here so the package builds with the current Swift 6.1 toolchain.

## Provenance

- Upstream repository: https://github.com/swiftlang/swift-tools-protocols
- Modules vendored:
  - `LanguageServerProtocol` — LSP types, requests, notifications, and the
    `Connection`/`MessageHandler` contracts (zero external dependencies).
  - `LanguageServerProtocolTransport` — `JSONRPCConnection`, `LocalConnection`,
    and JSON-RPC message framing.
  - `SKLogging` — logging used by the transport.
- `BuildServerMessageDependencyTracker.swift` was intentionally **removed** from
  the transport because it imports the unrelated `BuildServerProtocol` module,
  which this server does not need. No other upstream source is modified.

## License

Vendored code is licensed under the Apache License, Version 2.0 (see
`LICENSE.txt` and the per-file headers). It remains copyright Apple Inc. and the
Swift project authors. Grammar Workbench's own MIT license does not apply to
these files.

## Updating

To refresh the vendored copy, fetch `swiftlang/swift-tools-protocols` and copy:

    cp -R <checkout>/Sources/LanguageServerProtocol   Sources/
    cp -R <checkout>/Sources/LanguageServerProtocolTransport Sources/
    cp -R <checkout>/Sources/SKLogging                Sources/
    rm Sources/LanguageServerProtocolTransport/BuildServerMessageDependencyTracker.swift

## Moving to the upstream package

The upstream package currently requires Swift tools version 6.2. When the project
moves to a Swift 6.2+ toolchain, delete this directory and depend on the upstream
package instead:

    .package(url: "https://github.com/swiftlang/swift-tools-protocols.git", branch: "main")

then replace the three vendored targets with the `LanguageServerProtocol` and
`LanguageServerProtocolTransport` products.
