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
print("core-consumer-ok")
