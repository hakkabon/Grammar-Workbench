import Foundation
import GrammarWorkbench
import Testing

private let projectGrammar = #"""
%token ID /[a-z]+/
%skip /\s+/
%start List
List : List ',' ID | ID ;
"""#

private func projectManifest() -> GrammarProjectManifest {
    GrammarProjectManifest(
        name: "Example Language",
        grammar: .init(source: projectGrammar),
        sources: [
            .init(id: "main", path: "Sources/main.example", text: "one, two", revision: 1),
            .init(id: "library", path: "Sources/library.example", text: "three", revision: 4)
        ],
        tests: [
            .init(name: "list", input: "one, two", expectation: .accept),
            .init(name: "incomplete", input: "one,", expectation: .reject)
        ],
        generators: [
            .init(generator: "bnf", outputDirectory: "Generated", options: .init(["name": "Example"]))
        ]
    )
}

@Test func projectManifestRoundTripsAsAValidatedPortableEnvelope() throws {
    let manifest = projectManifest()
    let data = try GrammarProjectCodec.encode(manifest)
    let decoded = try GrammarProjectCodec.decode(data)

    #expect(decoded == manifest)
    #expect(decoded.kind == GrammarProjectManifest.kindIdentifier)
    #expect(decoded.apiVersion == GrammarWorkbenchAPI.version)
    #expect(String(decoding: data, as: UTF8.self).contains("grammar-workbench-project"))
}

@Test func projectManifestRejectsUnsafeAndAmbiguousConfiguration() throws {
    var unsafe = projectManifest()
    unsafe.sources[0].path = "../outside.example"
    #expect(throws: GrammarProjectError.self) { try GrammarProjectCodec.validate(unsafe) }

    var duplicate = projectManifest()
    duplicate.sources.append(.init(id: "main", path: "Sources/other.example", text: "one"))
    #expect(throws: GrammarProjectError.self) { try GrammarProjectCodec.validate(duplicate) }

    var duplicateTarget = projectManifest()
    duplicateTarget.generators.append(.init(
        id: "bnf", generator: "bnf", outputDirectory: "Other"
    ))
    #expect(throws: GrammarProjectError.self) { try GrammarProjectCodec.validate(duplicateTarget) }
}

@Test func projectCodecRejectsFutureSchemasKindsAndAPIs() throws {
    let data = try GrammarProjectCodec.encode(projectManifest())
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object["schemaVersion"] = 99
    #expect(throws: GrammarProjectError.self) {
        try GrammarProjectCodec.decode(JSONSerialization.data(withJSONObject: object))
    }
    object["schemaVersion"] = GrammarProjectManifest.currentSchemaVersion
    object["kind"] = "another-project"
    #expect(throws: GrammarProjectError.self) {
        try GrammarProjectCodec.decode(JSONSerialization.data(withJSONObject: object))
    }
    object["kind"] = GrammarProjectManifest.kindIdentifier
    object["apiVersion"] = 99
    #expect(throws: GrammarProjectError.self) {
        try GrammarProjectCodec.decode(JSONSerialization.data(withJSONObject: object))
    }
}

@Test func projectWorkspaceAnalyzesEditsAndIndexesAllDocuments() async throws {
    let workspace = try GrammarProjectWorkspace(manifest: projectManifest())
    let initial = try await workspace.analyze()

    #expect(initial.isSuccessful)
    #expect(initial.documents.map(\.documentID) == ["main", "library"])
    #expect(initial.index.entries(named: "List").count == 3)
    #expect(initial.tests.allPassed)

    let changed = try await workspace.apply(
        documentID: "main",
        edits: [.init(
            range: .init(
                start: .init(line: 0, utf16Column: 5),
                end: .init(line: 0, utf16Column: 8)
            ),
            replacement: "four"
        )],
        revision: 2
    )
    let main = try #require(changed.documents.first { $0.documentID == "main" })
    #expect(main.text.text == "one, four")
    #expect(main.incrementalLexing.strategy == .incremental)
    #expect(main.incrementalParsing.strategy == .incremental)
    #expect(changed.index.entries(documentID: "library").count > 0)
    #expect(await workspace.projectManifest().sources[0].text == "one, four")
}

@Test func projectWorkspaceRebuildsAllDocumentsForGrammarAndRunsTargets() async throws {
    let workspace = try GrammarProjectWorkspace(manifest: projectManifest())
    _ = try await workspace.analyze()
    let refreshed = try await workspace.updateGrammar(.init(
        source: projectGrammar + "\nUnused : 'unused' ;"
    ))
    #expect(refreshed.documents.allSatisfy { $0.grammarRevision == 1 })
    #expect(refreshed.documents.allSatisfy { $0.parse.status == .accepted })

    let generated = try await workspace.generate()
    #expect(generated.count == 1)
    #expect(generated[0].target.outputDirectory == "Generated")
    #expect(generated[0].result.files.first?.suggestedFilename == "Example.bnf")
    let parsed = try await workspace.parseAll()
    #expect(parsed.results.map(\.id) == ["main", "library"])
    #expect(parsed.accepted == 2)
}

@Test func projectWorkspaceReportsRejectedDocumentsWithoutDiscardingTheirIndexes() async throws {
    var manifest = projectManifest()
    manifest.sources[1].text = "three,"
    let workspace = try GrammarProjectWorkspace(manifest: manifest)
    let analysis = try await workspace.analyze()

    #expect(!analysis.isSuccessful)
    #expect(analysis.documents[1].parse.status != .accepted)
    #expect(!analysis.index.entries(documentID: "library").isEmpty)
}

@Test func projectWorkspaceReconcilesSourceAndConfigurationLifecycle() async throws {
    let workspace = try GrammarProjectWorkspace(manifest: projectManifest())
    _ = try await workspace.analyze()
    let replaced = try await workspace.replaceSources([
        .init(id: "main", path: "Sources/main.example", text: "one, four", revision: 2),
        .init(id: "new", path: "Sources/new.example", text: "five", revision: 1)
    ])

    #expect(replaced.documents.map(\.documentID) == ["main", "new"])
    #expect(replaced.index.entries(documentID: "library").isEmpty)
    #expect(replaced.documents[0].incrementalParsing.strategy == .incremental)

    let withoutTests = await workspace.replaceTests([])
    #expect(withoutTests.tests.results.isEmpty)
    let withoutGenerators = try await workspace.replaceGeneratorTargets([])
    #expect(withoutGenerators.manifest.generators.isEmpty)
    #expect(try await workspace.generate().isEmpty)
}
