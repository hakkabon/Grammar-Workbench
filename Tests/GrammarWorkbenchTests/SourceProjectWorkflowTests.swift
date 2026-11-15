import Foundation
import Testing
@testable import GrammarWorkbenchCore
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

@Test func grammarDraftImpactReportsRegressionAndSavesRepairedGrammar() throws {
    let fixture = sourceProjectRoot().appendingPathComponent("Examples/SourceProject")
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.copyItem(at: fixture, to: folder)
    defer { try? FileManager.default.removeItem(at: folder) }
    let descriptor = folder.appendingPathComponent(GrammarSourceProjectDescriptor.preferredFilename)
    let project = try GrammarSourceProjectLoader.load(at: descriptor)
    let grammar = project.manifest.grammar
    let baseline = GrammarWorkbenchAPI.compile(.init(
        source: grammar.source, algorithm: grammar.algorithm, notation: grammar.notation))
    try #require(baseline.succeeded)

    func check(_ draft: String) -> GrammarDraftImpact {
        .compare(draft: draft, baseline: baseline, sources: project.manifest.sources)
    }
    let invalid = check("%start E\nE :")
    #expect(!invalid.compiled)
    #expect(!invalid.diagnostics.isEmpty)
    #expect(invalid.examples.isEmpty)

    let regressed = check(grammar.source
        .replacingOccurrences(of: "E '+' E | ", with: "")
        .replacingOccurrences(of: "%left '+'\n", with: ""))
    #expect(regressed.compiled)
    #expect(regressed.removedRules.count == 1)
    #expect(regressed.examples.first?.regressed == true)
    #expect(regressed.examples.first?.path == "Sources/main.expr")
    #expect(regressed.examples.first?.range?.start.column == 7)

    let repaired = grammar.source + "\n"
    #expect(check(repaired).examples.first?.after == .accepted)
    try GrammarSourceProjectLoader.saveGrammar(repaired, in: project, replacing: grammar.source)
    #expect(try GrammarSourceProjectLoader.load(at: descriptor).manifest.grammar.source == repaired)
    do {
        try GrammarSourceProjectLoader.saveGrammar(grammar.source, in: project, replacing: grammar.source)
        Issue.record("Saving over a changed grammar should fail")
    } catch GrammarSourceProjectError.grammarChangedOnDisk {
    }
}
