import Foundation
import GrammarWorkbenchCore
import Testing

@Test func coreFacadeCompilesAndReexportsPortableContracts() throws {
    #expect(GrammarWorkbenchCoreModule.apiVersion == GrammarWorkbenchAPI.version)
    let compilation = GrammarWorkbenchAPI.compile(.init(source: "%start S\nS : 'ok' ;"))
    #expect(compilation.succeeded)
    #expect(compilation.parse("ok").status == .accepted)

    let graph = GrammarGraph(
        id: "portable", title: "Portable graph",
        nodes: [.init(id: "root", label: "root")], edges: []
    )
    let encoded = try JSONEncoder().encode(graph)
    #expect(try JSONDecoder().decode(GrammarGraph.self, from: encoded) == graph)
#if os(macOS)
    #expect(GrammarGraphLayoutEngine.availability == .swiftLayout)
#else
    #expect(GrammarGraphLayoutEngine.availability == .interchangeOnly)
#endif
}
