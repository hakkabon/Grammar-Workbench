import Foundation
import Testing
@testable import GrammarWorkbench

private func sourceProjectRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

@Test func sourceAssociationsSupportRecursiveAndFilenameGlobs() {
    let recursive = GrammarSourceAssociation(pattern: "Sources/**/*.expr", languageID: "expression")
    let filename = GrammarSourceAssociation(pattern: "*.expr", languageID: "expression")

    #expect(recursive.matches(relativePath: "Sources/main.expr"))
    #expect(recursive.matches(relativePath: "Sources/nested/other.expr"))
    #expect(!recursive.matches(relativePath: "Tests/main.expr"))
    #expect(filename.matches(relativePath: "main.expr"))
    #expect(!filename.matches(relativePath: "Sources/main.expr"))
}

@Test func sourceProjectDescriptorRoundTripsAndRejectsUnsafeConfiguration() throws {
    let descriptor = GrammarSourceProjectDescriptor(
        name: "Tiny",
        grammar: .init(path: "Grammar.grammar", languageID: "tiny"),
        associations: [.init(pattern: "Sources/**/*.tiny", languageID: "tiny")]
    )
    let decoded = try GrammarSourceProjectCodec.decode(GrammarSourceProjectCodec.encode(descriptor))
    #expect(decoded == descriptor)

    var unsafe = descriptor
    unsafe.grammar.path = "../Grammar.grammar"
    #expect(throws: GrammarSourceProjectError.self) {
        try GrammarSourceProjectCodec.validate(unsafe)
    }
}

@Test func sourceProjectLoaderCreatesAReproducibleAnalyzableManifest() async throws {
    let descriptorURL = sourceProjectRoot()
        .appendingPathComponent("Examples/SourceProject/.grammar-workbench-source.json")
    let loaded = try GrammarSourceProjectLoader.load(at: descriptorURL)

    #expect(loaded.descriptor.grammar.languageID == "expression")
    #expect(loaded.manifest.sources.map(\.path) == ["Sources/main.expr"])
    #expect(loaded.manifest.sources[0].text.contains("alpha"))

    let analysis = try await GrammarProjectWorkspace(manifest: loaded.manifest).analyze()
    #expect(analysis.isSuccessful)
    #expect(analysis.documents.first?.parse.status == .accepted)
}
