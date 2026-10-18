import Foundation
import GrammarWorkbenchCore

let source = "%start S\nS : 'portable' ;"
let compilation = GrammarWorkbenchAPI.compile(.init(source: source))
guard compilation.succeeded, compilation.parse("portable").status == .accepted else {
    fatalError("Portable core compilation failed")
}
let graph = GrammarGraph(
    id: "core-consumer", title: "Core consumer",
    nodes: [.init(id: "S", label: "S")], edges: []
)
guard try JSONDecoder().decode(GrammarGraph.self, from: JSONEncoder().encode(graph)) == graph else {
    fatalError("Portable graph interchange failed")
}

struct PublicBoundaryExtension: GrammarWorkbenchExtension {
    let manifest = GrammarWorkbenchExtensionManifest(
        id: "org.grammar-workbench.consumer",
        displayName: "Consumer extension",
        version: "1.0.0",
        summary: "Verifies the public extension boundary from another package.",
        commands: [
            .init(
                id: "production-count", displayName: "Production count",
                summary: "Counts productions through immutable snapshots.", kind: .analysis
            )
        ]
    )

    func run(_ request: GrammarExtensionRequest) async throws -> GrammarExtensionResult {
        .init(
            extensionIdentifier: request.extensionIdentifier,
            commandIdentifier: request.commandIdentifier,
            summary: "\(request.context.grammar?.productions.count ?? 0) productions"
        )
    }
}

let extensionRegistry = GrammarWorkbenchExtensionRegistry()
try await extensionRegistry.register(PublicBoundaryExtension())
let extensionResult = try await extensionRegistry.run(
    extensionIdentifier: "org.grammar-workbench.consumer",
    commandIdentifier: "production-count",
    compilation: compilation
)
guard extensionResult.summary == "1 productions" else {
    fatalError("Public extension boundary failed")
}
print("core-consumer-ok")
