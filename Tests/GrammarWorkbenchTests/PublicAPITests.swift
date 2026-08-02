import Foundation
import Testing
import GrammarWorkbench

@Test func publicRecoveryOptionsCanPreferGrammarSpecificInsertion() throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(
        source: "%start S\nS : 'a' Choice ;\nChoice : 'b' | 'c' ;"
    ))
    let result = compilation.parse(
        "a",
        options: .init(synchronizationTerminals: [";"], preferredInsertions: ["c"])
    )

    #expect(result.status == .acceptedWithRecovery)
    #expect(result.diagnostics.first?.recovery == .insertedToken)
    #expect(result.diagnostics.first?.recoverySymbol == "c")
}

private let publicGrammar = """
%token ID /[a-z]+/
%skip /\\s+/
%start List
List : List ',' ID | ID ;
"""

private struct IntegerSumReducer: GrammarSemanticReducer {
    func terminal(_ token: GrammarInputTokenSnapshot, node: GrammarSyntaxNode) throws -> Int {
        Int(token.lexeme) ?? 0
    }

    func missing(symbol: String, node: GrammarSyntaxNode) throws -> Int { 0 }

    func reduce(
        production: GrammarProductionSnapshot, children: [Int], node: GrammarSyntaxNode
    ) throws -> Int {
        children.reduce(0, +)
    }
}

@Test func structuredSyntaxTreeAndSemanticReducerPreserveSourceInformation() throws {
    let source = "%token INT /[0-9]+/\n%skip /\\s+/\n%start Sum\nSum : Sum '+' INT | INT ;"
    let compilation = GrammarWorkbenchAPI.compile(.init(source: source))
    let result = try compilation.parse("12 + 30", using: IntegerSumReducer())

    #expect(result.value == 42)
    #expect(result.parse.syntaxTree?.symbol == "Sum")
    #expect(result.parse.syntaxTree?.range?.start.offset == 0)
    #expect(result.parse.syntaxTree?.range?.end.offset == 7)
    #expect(result.parse.syntaxTree?.descendants(named: "INT").map(\.token?.lexeme) == ["12", "30"])
    #expect(result.parse.syntaxTree?.production != nil)
}

@Test func structuredSyntaxTreeMarksRecoveryInsertions() throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: publicGrammar))
    let result = compilation.parse("one two")
    let missing = result.syntaxTree?.descendants(named: ",").first
    #expect(missing?.isMissing == true)
    #expect(missing?.token == nil)
}

@Test func parseResultDecodesLegacyJSONWithoutStructuredTree() throws {
    let result = GrammarWorkbenchAPI.compile(.init(source: publicGrammar)).parse("one")
    let encoded = try JSONEncoder().encode(result)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "syntaxTree")
    let legacy = try JSONSerialization.data(withJSONObject: object)
    #expect(try JSONDecoder().decode(GrammarParseResult.self, from: legacy).syntaxTree == nil)
}

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

@Test func publicAPIExposesLocatedRecoveryDiagnostics() throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: publicGrammar))
    let result = compilation.parse("one two")
    #expect(result.status == .acceptedWithRecovery)
    #expect(result.diagnostics.count == 1)
    #expect(result.diagnostics[0].recovery == .insertedToken)
    #expect(result.diagnostics[0].recoverySymbol == ",")
    #expect(result.diagnostics[0].expected.contains(","))
    #expect(result.diagnostics[0].range?.start.column == 5)
    #expect(result.tree?.contains("⟨missing ,⟩") == true)

    let strict = compilation.parse("one two", options: .init(enablesRecovery: false))
    #expect(strict.status == .rejected)
    #expect(strict.diagnostics.isEmpty)
}

@Test func publicAPIExposesLexerModesAndTokenOrigins() throws {
    let source = #"""
    %token QUOTE /"/ %push STRING
    %mode STRING
    %token TEXT /[^"]+/
    %token QUOTE /"/ %pop
    %start S
    S : QUOTE TEXT QUOTE ;
    """#
    let compilation = GrammarWorkbenchAPI.compile(.init(source: source))
    #expect(compilation.succeeded)
    #expect(compilation.lexerAnalysis?.reachableModes == ["DEFAULT", "STRING"])
    let result = compilation.lex("\"content\"")
    #expect(result.tokens.map(\.mode) == ["DEFAULT", "STRING", "STRING"])
    #expect(result.finalModeStack == ["DEFAULT"])
}
