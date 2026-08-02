import Foundation
import Testing
import GrammarWorkbench

private let generatorGrammar = """
%token ID /[a-z]+/
%start List
List : List ',' ID | ID | ;
"""

private struct SummaryGenerator: GrammarGenerator {
    let descriptor = GrammarGeneratorDescriptor(
        id: "test-summary", displayName: "Test Summary", summary: "Test extension",
        defaultFileExtension: "txt", mediaType: "text/plain",
        options: [.init(name: "name", summary: "Output base name.", defaultValue: "grammar")]
    )

    func generate(
        from compilation: GrammarCompilation,
        options: GrammarGeneratorOptions
    ) throws -> GrammarGenerationResult {
        let name = options["name"] ?? "grammar"
        let count = compilation.grammar?.productions.count ?? 0
        return .init(generator: descriptor, files: [
            .init(suggestedFilename: "\(name).txt", mediaType: "text/plain", text: "\(count) productions")
        ])
    }
}

private struct UnsafeOutputGenerator: GrammarGenerator {
    let filenames: [String]
    let descriptor = GrammarGeneratorDescriptor(
        id: "unsafe-output", displayName: "Unsafe output", summary: "Test extension",
        defaultFileExtension: "txt", mediaType: "text/plain"
    )

    func generate(
        from compilation: GrammarCompilation,
        options: GrammarGeneratorOptions
    ) throws -> GrammarGenerationResult {
        .init(generator: descriptor, files: filenames.map {
            .init(suggestedFilename: $0, mediaType: "text/plain", text: "test")
        })
    }
}

@Test func registryExposesBuiltInsAndRunsExternalGenerator() async throws {
    let registry = GrammarGeneratorRegistry()
    let compilation = GrammarWorkbenchAPI.compile(.init(source: generatorGrammar))

    #expect(await registry.availableGenerators().map(\.id) == ["artifact-json", "bnf", "swift"])
    try await registry.register(SummaryGenerator())
    let result = try await registry.generate(
        identifier: "test-summary", from: compilation, options: .init(["name": "List"])
    )

    #expect(result.files.first?.suggestedFilename == "List.txt")
    #expect(result.files.first?.text == "3 productions")
    #expect(await registry.unregister(identifier: "test-summary"))
    await #expect(throws: GrammarGeneratorRegistryError.self) {
        try await registry.generate(identifier: "test-summary", from: compilation)
    }
}

@Test func registryRejectsDuplicateAndEmptyGeneratorResults() async throws {
    let registry = GrammarGeneratorRegistry(includingBuiltIns: false)
    try await registry.register(SummaryGenerator())
    await #expect(throws: GrammarGeneratorRegistryError.self) {
        try await registry.register(SummaryGenerator())
    }
}

@Test func registryValidatesOptionsAndOutputFilenames() async throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: generatorGrammar))
    let registry = GrammarGeneratorRegistry()

    await #expect(throws: GrammarGeneratorRegistryError.self) {
        try await registry.generate(
            identifier: "swift", from: compilation,
            options: .init(["unknown": "value"])
        )
    }
    await #expect(throws: GrammarGeneratorRegistryError.self) {
        try await registry.generate(
            identifier: "swift", from: compilation,
            options: .init(["accessLevel": "package"])
        )
    }

    try await registry.register(UnsafeOutputGenerator(filenames: ["../outside.txt"]))
    await #expect(throws: GrammarGeneratorRegistryError.self) {
        try await registry.generate(identifier: "unsafe-output", from: compilation)
    }
    try await registry.register(
        UnsafeOutputGenerator(filenames: ["Result.txt", "result.TXT"]),
        replacingExisting: true
    )
    await #expect(throws: GrammarGeneratorRegistryError.self) {
        try await registry.generate(identifier: "unsafe-output", from: compilation)
    }
}

@Test func portableBNFPreservesAlternativesAndEmptyProductions() throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: generatorGrammar))
    let result = try BNFGrammarGenerator().generate(
        from: compilation, options: .init(["name": "lists"])
    )
    let text = try #require(result.files.first?.text)

    #expect(result.files.first?.suggestedFilename == "lists.bnf")
    #expect(text.contains(#"<List> ::= <List> "," "ID""#))
    #expect(text.contains("| ε"))
}

@Test func swiftBuiltInUsesGenericOptions() throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: "%start S\nS : 'id' ;"))
    let result = try SwiftGrammarGenerator().generate(
        from: compilation,
        options: .init(["typeName": "CustomParser", "accessLevel": "internal"])
    )
    let text = try #require(result.files.first?.text)
    #expect(result.files.first?.suggestedFilename == "CustomParser.swift")
    #expect(text.contains("enum CustomParser"))
    #expect(!text.contains("public enum CustomParser"))
}

@Test func publicArtifactInterchangeRoundTripsAndValidatesEnvelope() throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: generatorGrammar, algorithm: .slr))
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let data = try GrammarInterchangeCodec.encodeArtifact(compilation: compilation, generatedAt: date)
    let decoded = try GrammarInterchangeCodec.decodeArtifact(data)

    #expect(decoded.schemaVersion == GrammarArtifactInterchange.currentSchemaVersion)
    #expect(decoded.generatedAt == date)
    #expect(decoded.artifact == compilation.artifact)
    #expect(decoded.artifact.algorithm == .slr)

    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object["kind"] = "some-other-tool"
    let invalid = try JSONSerialization.data(withJSONObject: object)
    #expect(throws: GrammarInterchangeError.self) {
        try GrammarInterchangeCodec.decodeArtifact(invalid)
    }
}
