import Foundation
import GrammarWorkbench
import Testing

private let kitGrammar = #"""
%token LET /let\b/
%token USE /use\b/
%token ID /[A-Za-z_][A-Za-z0-9_]*/
%token SEMI /;/
%skip /\s+/
%start Program
Program : Program Statement | Statement ;
Statement : LET ID SEMI | USE ID SEMI ;
"""#

private func languageKitManifest(
    tests: [WorkbenchTestCase] = [
        .init(name: "declaration", input: "let alpha;", expectation: .accept),
        .init(name: "invalid", input: "let ;", expectation: .reject)
    ]
) throws -> GrammarSemanticLanguageKitManifest {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: kitGrammar))
    let model = try GrammarSemanticModel(compilation: compilation)
    let definition = try #require(
        model.productions(lhs: "Statement", rhs: ["LET", "ID", "SEMI"]).first
    )
    let reference = try #require(
        model.productions(lhs: "Statement", rhs: ["USE", "ID", "SEMI"]).first
    )
    return .init(
        identifier: "org.example.tiny-language", name: "Tiny Language", version: "1.0.0",
        fileExtensions: ["tiny"], grammar: .init(source: kitGrammar),
        semantics: .init(rules: [
            .init(
                tokenKind: "ID", enclosingProduction: definition.id,
                kind: "variable", role: .definition
            ),
            .init(
                tokenKind: "ID", enclosingProduction: reference.id,
                kind: "variable", role: .reference
            )
        ]),
        tests: tests,
        generators: [.init(generator: "bnf", outputDirectory: "Generated")],
        metadata: ["homepage": "https://example.org/tiny"]
    )
}

@Test func semanticLanguageKitRoundTripsAndValidatesItsContract() throws {
    let manifest = try languageKitManifest()
    let encoded = try GrammarSemanticLanguageKitCodec.encode(manifest)
    let kit = try GrammarSemanticLanguageKitCodec.decode(encoded, requirePassingTests: true)

    #expect(kit.manifest == manifest)
    #expect(kit.isConformant)
    #expect(kit.conformance.passed == 2)
    #expect(kit.supportsFile(named: "Sources/main.TINY"))
    #expect(!kit.supportsFile(named: "README.md"))
    #expect(kit.semanticModel.productions.count == 4)
}

@Test func semanticLanguageKitCreatesProjectsAndSemanticServices() async throws {
    let kit = try GrammarSemanticLanguageKit.compile(try languageKitManifest())
    let result = try await kit.analyze(
        name: "Kit consumer",
        sources: [
            .init(id: "definition", path: "Sources/Definition.tiny", text: "let alpha;", revision: 1),
            .init(id: "use", path: "Sources/Use.tiny", text: "use alpha;", revision: 1)
        ]
    )

    #expect(result.isSuccessful)
    #expect(result.project.manifest.name == "Kit consumer")
    #expect(result.project.manifest.tests == kit.manifest.tests)
    #expect(result.project.manifest.generators == kit.manifest.generators)
    #expect(result.semantics.workspaceSymbols().map(\.name) == ["alpha"])
    #expect(result.semantics.dependencies.count == 1)
}

@Test func semanticLanguageKitRejectsStaleAndShadowedSemanticRules() throws {
    var unknown = try languageKitManifest()
    unknown.semantics = .init(rules: [
        .init(tokenKind: "MISSING", kind: "variable", role: .definition)
    ])
    #expect(throws: GrammarSemanticLanguageKitError.self) {
        try GrammarSemanticLanguageKit.compile(unknown)
    }

    var shadowed = try languageKitManifest()
    shadowed.semantics = .init(rules: [
        .init(tokenKind: "ID", kind: "first", role: .definition),
        .init(tokenKind: "ID", kind: "second", role: .reference)
    ])
    #expect(throws: GrammarSemanticLanguageKitError.self) {
        try GrammarSemanticLanguageKit.compile(shadowed)
    }
}

@Test func semanticLanguageKitCanInspectButRejectFailingConformance() throws {
    let manifest = try languageKitManifest(tests: [
        .init(name: "wrong expectation", input: "let alpha;", expectation: .reject)
    ])
    let inspected = try GrammarSemanticLanguageKit.compile(
        manifest, requirePassingTests: false
    )
    #expect(!inspected.isConformant)
    #expect(inspected.conformance.failed == 1)
    #expect(throws: GrammarSemanticLanguageKitError.self) {
        try GrammarSemanticLanguageKit.compile(manifest)
    }
}

@Test func semanticLanguageKitRejectsUnsafeIdentityAndExtensions() throws {
    var invalid = try languageKitManifest()
    invalid.identifier = "not namespaced"
    #expect(throws: GrammarSemanticLanguageKitError.self) {
        try GrammarSemanticLanguageKit.compile(invalid)
    }
    invalid = try languageKitManifest()
    invalid.fileExtensions = [".tiny"]
    #expect(throws: GrammarSemanticLanguageKitError.self) {
        try GrammarSemanticLanguageKit.compile(invalid)
    }
}

@Test func semanticLanguageKitRegistryDiscoversFilesAndProtectsIdentity() async throws {
    let registry = GrammarSemanticLanguageKitRegistry()
    let manifest = try languageKitManifest()
    _ = try await registry.register(manifest)
    #expect(await registry.registeredIdentifiers == [manifest.identifier])
    #expect(await registry.kits(forFile: "Main.tiny").map(\.manifest.identifier) == [manifest.identifier])
    #expect(await registry.kits(forFile: "Main.other").isEmpty)
    await #expect(throws: GrammarSemanticLanguageKitError.self) {
        try await registry.register(manifest)
    }
    try await registry.unregister(identifier: manifest.identifier)
    #expect(await registry.registeredIdentifiers.isEmpty)
}

@Test func semanticLanguageKitRejectsSourcesOutsideItsExtensionPolicy() async throws {
    let kit = try GrammarSemanticLanguageKit.compile(try languageKitManifest())
    #expect(throws: GrammarSemanticLanguageKitError.self) {
        try kit.makeWorkspace(sources: [
            .init(id: "main", path: "Sources/main.wrong", text: "let alpha;")
        ])
    }
}
