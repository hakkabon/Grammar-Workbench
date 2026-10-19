# Public extension boundary

Grammar Workbench 1.0.27 added an explicit extension host for trusted Swift
packages. It is designed for grammar analyses, portable exports, and
reproducible research commands that need stable Workbench data but do not own
parsing or semantic execution.

## Contract

An extension implements `GrammarWorkbenchExtension` and publishes a
`GrammarWorkbenchExtensionManifest`. The manifest is Codable discovery data:
it carries a reverse-domain identifier, semantic version, minimum Workbench API
version, and one or more typed command descriptors. Registration validates the
whole manifest before changing registry state.

```swift
import GrammarWorkbenchCore

struct ProductionCountExtension: GrammarWorkbenchExtension {
    let manifest = GrammarWorkbenchExtensionManifest(
        id: "org.example.production-count",
        displayName: "Production count",
        version: "1.0.0",
        summary: "Reports the number of productions.",
        commands: [
            .init(
                id: "count", displayName: "Count productions",
                summary: "Counts productions in a compiled grammar.",
                kind: .analysis
            )
        ]
    )

    func run(_ request: GrammarExtensionRequest) async throws
        -> GrammarExtensionResult
    {
        let count = request.context.grammar?.productions.count ?? 0
        return .init(
            extensionIdentifier: request.extensionIdentifier,
            commandIdentifier: request.commandIdentifier,
            summary: "\(count) productions"
        )
    }
}

let compilation = GrammarWorkbenchAPI.compile(.init(source: grammarSource))
let registry = GrammarWorkbenchExtensionRegistry()
try await registry.register(ProductionCountExtension())
let result = try await registry.run(
    extensionIdentifier: "org.example.production-count",
    commandIdentifier: "count",
    compilation: compilation
)
```

The context contains only immutable public values: the compilation request,
diagnostics, grammar and analysis summaries, lexer analysis, portable LR
artifact, and construction measurements. It deliberately does not expose the
Workbench's private construction or runtime objects. The Codable registry
snapshot supports discovery without executing a command.

Commands receive normalized string options. Declared defaults are applied by
the host, unknown options and disallowed values are rejected, and a command
returns only a summary, portable findings, named in-memory files, and string
properties. The host validates result identity, unique finding and file names,
safe leaf filenames, and configured count and byte limits. It never writes a
file or changes a project on an extension's behalf.

## Ownership boundaries

Use the narrowest existing contract:

- Implement `GrammarGenerator` for code generators, documentation emitters,
  or build adapters. Its dedicated registry remains the canonical generation
  boundary.
- Implement `GrammarWorkbenchExtension` for opt-in analyses, research tools,
  and portable exports that are not generators.
- Implement `GrammarToolingTransport` when the concern is communication with a
  separate process or remote service.
- Add parser behavior to its owning parser-engine repository and expose it
  through Parser's contracts. An extension is not an alternate private parser
  backend.

The extension contract does not provide UI injection, parser-engine
replacement, semantic-reducer replacement, automatic filesystem discovery, or
dynamic library loading. Those exclusions keep Grammar, Parser, Compiler,
Grammar-REPL, and Workbench ownership intact.

## Trust and compatibility

Extensions are ordinary in-process Swift code and therefore must be trusted.
`GrammarWorkbenchExtensionRegistry` supplies concurrency isolation and bounded
portable outputs, not a security sandbox. Hosts needing fault or security
isolation should execute the extension in another process and bridge it through
a transport they control.

Extension schema 1 and Workbench API version 1 are separate compatibility
axes. A host rejects an unknown manifest schema or an extension whose minimum
host API is newer than the current API. Additive compatible command changes use
the extension's minor version; removed commands or changed meanings require an
extension major version. Registration is explicit and instance-local, and an
existing identifier is replaced only when the host opts in.

