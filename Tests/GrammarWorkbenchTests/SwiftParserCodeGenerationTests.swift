import Foundation
import Testing
import GrammarWorkbench

private let generatorGrammar = """
%token ID /[a-z]+/
%skip /\\s+/
%start List
List : List ',' ID | ID ;
"""

@Test func generatedSwiftParserCompilesAndParsesInput() throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: generatorGrammar))
    let source = try compilation.generateSwiftParser(options: .init(typeName: "ListParser"))
    #expect(source.contains("public enum ListParser"))
    #expect(source.contains("static func parse(_ source: String)"))
    #expect(source.contains("LexerRule(kind: \"ID\""))

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("GrammarWorkbench-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let generatedURL = directory.appendingPathComponent("Generated.swift")
    let mainURL = directory.appendingPathComponent("main.swift")
    let executableURL = directory.appendingPathComponent("parser-test")
    try source.write(to: generatedURL, atomically: true, encoding: .utf8)
    try """
    import Foundation
    let tree = try ListParser.parse("one, two")
    print(tree.symbol)
    print(try ListParser.tokenize("one, two").map(\\.kind).joined(separator: ","))
    let recovered = try ListParser.parseRecovering("one two")
    print(recovered.completed, recovered.diagnostics.first?.recovery == .insertedToken)
    """.write(to: mainURL, atomically: true, encoding: .utf8)

    let compile = try run("/usr/bin/xcrun", ["swiftc", generatedURL.path, mainURL.path, "-o", executableURL.path])
    #expect(compile.status == 0, Comment(rawValue: compile.output))
    let execution = try run(executableURL.path, [])
    #expect(execution.status == 0, Comment(rawValue: execution.output))
    #expect(execution.output == "List\nID,,,ID\ntrue true\n")
}

@Test func generatedParserSupportsLegacyTokenInput() throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: "%start S\nS : 'id' '+' 'id' ;"))
    let source = try compilation.generateSwiftParser()
    #expect(source.contains("whitespaceTokens"))
    #expect(source.contains("symbol: \"+\""))
    #expect(!source.contains("LexerRule(kind: \"id\""))
}

@Test func generatedSourceIsDeterministic() throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: generatorGrammar))
    #expect(try compilation.generateSwiftParser() == compilation.generateSwiftParser())
}

@Test func generatedParserPreservesLexerModeTransitions() throws {
    let grammar = #"""
    %token ID /[a-z]+/
    %token QUOTE /"/ %push STRING
    %skip /\s+/
    %mode STRING
    %token TEXT /[^"]+/
    %token QUOTE /"/ %pop
    %start S
    S : ID QUOTE TEXT QUOTE ;
    """#
    let compilation = GrammarWorkbenchAPI.compile(.init(source: grammar))
    let source = try compilation.generateSwiftParser(options: .init(typeName: "ModeParser"))
    #expect(source.contains("mode: \"STRING\""))
    #expect(source.contains("action: .push(\"STRING\")"))

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("GrammarWorkbenchModes-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let generatedURL = directory.appendingPathComponent("Generated.swift")
    let mainURL = directory.appendingPathComponent("main.swift")
    let executableURL = directory.appendingPathComponent("mode-parser-test")
    try source.write(to: generatedURL, atomically: true, encoding: .utf8)
    try """
    import Foundation
    let tokens = try ModeParser.tokenize("say \\"hello world\\"")
    print(tokens.map(\\.kind).joined(separator: ","))
    print(tokens.map(\\.mode).joined(separator: ","))
    """.write(to: mainURL, atomically: true, encoding: .utf8)
    let compile = try run("/usr/bin/xcrun", ["swiftc", generatedURL.path, mainURL.path, "-o", executableURL.path])
    #expect(compile.status == 0, Comment(rawValue: compile.output))
    let execution = try run(executableURL.path, [])
    #expect(execution.status == 0, Comment(rawValue: execution.output))
    #expect(execution.output == "ID,QUOTE,TEXT,QUOTE\nDEFAULT,DEFAULT,STRING,STRING\n")
}

@Test func generatorRejectsInvalidNamesAndUnresolvedConflicts() throws {
    let deterministic = GrammarWorkbenchAPI.compile(.init(source: generatorGrammar))
    #expect(throws: SwiftParserGenerationError.self) {
        try deterministic.generateSwiftParser(options: .init(typeName: "not valid"))
    }

    let ambiguous = GrammarWorkbenchAPI.compile(.init(source: "%start E\nE : E '+' E | 'id' ;"))
    #expect(throws: SwiftParserGenerationError.self) {
        try ambiguous.generateSwiftParser()
    }
    let selected = try ambiguous.generateSwiftParser(options: .init(conflictPolicy: .preferShift))
    #expect(selected.contains("enum GeneratedParser"))
}

private func run(_ executable: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    return (process.terminationStatus, output)
}
