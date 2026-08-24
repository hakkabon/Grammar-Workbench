import Testing
import GrammarDiagramKit
@testable import GrammarWorkbench

@Suite("Diagram and REPL product integration")
struct DiagramAndREPLIntegrationTests {
    private let source = """
    %start S
    S : 'a' Tail
      | ;
    Tail : 'b' ;
    """

    @Test("Diagram adapter preserves alternatives, symbol kinds, and source identities")
    func diagramAdapter() throws {
        let compilation = GrammarWorkbenchAPI.compile(.init(source: source))
        #expect(GrammarDiagramAdapter.availableRules(in: compilation) == ["S", "Tail"])

        let adapted = try #require(GrammarDiagramAdapter.diagram(for: "S", in: compilation))
        let layout = LayoutEngine.compute(adapted.model, metrics: .standard)
        #expect(layout.nodes.contains { $0.kind.label == "a" && $0.kind.isTerminal })
        #expect(layout.nodes.contains { $0.kind.label == "Tail" && $0.kind.isNonTerminal })
        #expect(layout.nodes.contains { $0.kind.label == "ε" })

        let symbolNode = try #require(layout.nodes.first { $0.kind.label == "Tail" })
        let selection = try #require(adapted.selection(for: symbolNode.elementID))
        #expect(selection.rule == "S")
        #expect(selection.symbol == "Tail")
        #expect(selection.symbolIndex == 1)
        #expect(selection.sourceRange.start.line == 2)
    }

    @Test("Unknown and invalid grammars produce no diagrams")
    func unavailableDiagrams() {
        let valid = GrammarWorkbenchAPI.compile(.init(source: source))
        #expect(GrammarDiagramAdapter.diagram(for: "Missing", in: valid) == nil)
        let invalid = GrammarWorkbenchAPI.compile(.init(source: "%start S\nS :"))
        #expect(GrammarDiagramAdapter.availableRules(in: invalid).isEmpty)
    }

    @Test("REPL uses compilation parsing and records inspectable results")
    func replParsing() throws {
        let compilation = GrammarWorkbenchAPI.compile(.init(source: source))
        var session = GrammarREPLSession(compilation: compilation)
        let emitted = session.submit("a b")

        #expect(emitted.map(\.kind) == [.input, .result])
        let parse = try #require(emitted.last?.parse)
        #expect(parse.status == .accepted)
        #expect(parse.tokens.map(\.kind) == ["a", "b"])
        #expect(session.transcript == emitted)
    }

    @Test("REPL commands select diagram rules, report history, and clear state")
    func replCommands() {
        let compilation = GrammarWorkbenchAPI.compile(.init(source: source))
        var session = GrammarREPLSession(compilation: compilation)

        #expect(session.submit(":rule Tail").last?.kind == .information)
        #expect(session.selectedRule == "Tail")
        #expect(session.submit(":rule Missing").last?.kind == .error)
        #expect(session.submit(":history").last?.text.contains(":rule Tail") == true)
        #expect(session.submit(":help").last?.text.contains(":rules") == true)
        _ = session.submit(":clear")
        #expect(session.transcript.isEmpty)
    }
}
