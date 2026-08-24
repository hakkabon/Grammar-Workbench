import Foundation
import Testing
@testable import GrammarWorkbench

@Suite("Interactive grammar exploration")
struct InteractiveGrammarExplorationTests {
    private let source = """
    %start Root
    Root : Item Tail ;
    Item : 'id' | ;
    Tail : ',' Item Tail | ;
    Dead : 'x' ;
    """

    @Test("Explorer projects rule facts, relationships, and source ranges")
    func ruleProjection() throws {
        let compilation = GrammarWorkbenchAPI.compile(.init(source: source))
        let snapshot = try GrammarInteractiveExplorer.snapshot(compilation, selectedRule: "Item")
        let item = try #require(snapshot.selected)

        #expect(snapshot.startRule == "Root")
        #expect(snapshot.pathFromStart == ["Root", "Item"])
        #expect(item.id == "Item")
        #expect(item.isReachable)
        #expect(item.isProductive)
        #expect(item.isNullable)
        #expect(item.incomingRules == ["Root", "Tail"])
        #expect(item.productions.count == 2)
        #expect(item.sourceRange?.start.line == 3)
        #expect(item.first == ["id"])
        #expect(Set(item.follow) == ["$", ","])
    }

    @Test("Explorer exposes recursion and unreachable rules without hiding them")
    func structuralStatuses() throws {
        let snapshot = try GrammarInteractiveExplorer.snapshot(
            GrammarWorkbenchAPI.compile(.init(source: source))
        )
        let tail = try #require(snapshot.rules.first { $0.id == "Tail" })
        let dead = try #require(snapshot.rules.first { $0.id == "Dead" })

        #expect(tail.isRecursive)
        #expect(tail.outgoingRules == ["Item", "Tail"])
        #expect(!dead.isReachable)
        #expect(dead.isProductive)
    }

    @Test("Search covers names, productions, FIRST, and FOLLOW")
    func search() throws {
        let snapshot = try GrammarInteractiveExplorer.snapshot(
            GrammarWorkbenchAPI.compile(.init(source: source))
        )
        #expect(GrammarInteractiveExplorer.matchingRules(in: snapshot, query: "Dead").map(\.id) == ["Dead"])
        #expect(GrammarInteractiveExplorer.matchingRules(in: snapshot, query: "x").map(\.id) == ["Dead"])
        #expect(GrammarInteractiveExplorer.matchingRules(in: snapshot, query: ",").map(\.id).contains("Item"))
        #expect(GrammarInteractiveExplorer.matchingRules(in: snapshot, query: "  ").count == 4)
    }

    @Test("Snapshot is stable Codable data and invalid compilations fail explicitly")
    func stableContract() throws {
        let compilation = GrammarWorkbenchAPI.compile(.init(source: source))
        let snapshot = try GrammarInteractiveExplorer.snapshot(compilation, selectedRule: "Missing")
        #expect(snapshot.selectedRule == "Root")
        let decoded = try JSONDecoder().decode(
            GrammarExplorationSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )
        #expect(decoded == snapshot)

        let invalid = GrammarWorkbenchAPI.compile(.init(source: "%start S\nS :"))
        #expect(throws: GrammarTransformationError.self) {
            try GrammarInteractiveExplorer.snapshot(invalid)
        }
    }
}
