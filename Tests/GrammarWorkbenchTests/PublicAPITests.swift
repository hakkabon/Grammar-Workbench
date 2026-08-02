import Foundation
import Testing
import GrammarWorkbench

private let publicGrammar = """
%token ID /[a-z]+/
%skip /\\s+/
%start List
List : List ',' ID | ID ;
"""

@Test func publicAPICompilesToStableSnapshots() throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: publicGrammar, algorithm: .lalr))

    #expect(GrammarWorkbenchAPI.version == 1)
    #expect(compilation.succeeded)
    #expect(compilation.grammar?.startSymbol == "List")
    #expect(compilation.artifact?.algorithm == .lalr)
    #expect(compilation.artifact?.states.isEmpty == false)
    #expect(compilation.artifact?.table.contains { $0.actions.contains { $0.kind == .accept } } == true)

    let data = try compilation.encodeArtifactSnapshot(prettyPrinted: false)
    let decoded = try JSONDecoder().decode(GrammarArtifactSnapshot.self, from: data)
    #expect(decoded.apiVersion == GrammarWorkbenchAPI.version)
    #expect(decoded.productions == compilation.artifact?.productions)
}

@Test func publicAPIProvidesLexerParserReplayAndTests() throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: publicGrammar))
    let lexed = compilation.lex("one, two")
    #expect(lexed.tokens.map(\.kind) == ["ID", ",", "ID"])
    #expect(lexed.tokens.map(\.lexeme) == ["one", ",", "two"])

    let parsed = compilation.parse("one, two")
    #expect(parsed.status == .accepted)
    #expect(parsed.tree?.hasPrefix("List") == true)
    #expect(parsed.trace.last?.action == "accept")

    let report = compilation.runTests([
        .init(name: "list", input: "one, two", expectation: .accept),
        .init(name: "incomplete", input: "one,", expectation: .reject)
    ])
    #expect(report.allPassed)
}

@Test func publicAPIInvalidCompilationFailsWithoutTrapping() {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: "%start Missing"))
    #expect(!compilation.succeeded)
    #expect(compilation.diagnostics.contains { $0.severity == .error })
    #expect(compilation.parse("anything").status == .invalidGrammar)

    let semanticallyInvalid = GrammarWorkbenchAPI.compile(.init(
        source: "%token ID\n%start S\nS : UNKNOWN ;"
    ))
    #expect(!semanticallyInvalid.succeeded)
}
