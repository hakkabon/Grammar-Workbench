import Foundation
import Testing
import UniformTypeIdentifiers
@testable import GrammarWorkbench

@MainActor
private func awaitRegeneration(_ store: ExplorerStore) async throws {
    for _ in 0..<200 {
        if !store.isRegenerating { return }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    Issue.record("Artifact regeneration did not finish within two seconds.")
}

@Test func documentRoundTripPreservesWorkbenchState() throws {
    let selectedID = UUID()
    let document = GrammarWorkbenchDocument(
        source: "%start S\nS : 'value' ;",
        algorithm: "Canonical LR(1)",
        samples: [
            WorkbenchSample(id: selectedID, name: "Valid", input: "value"),
            WorkbenchSample(name: "Invalid", input: "other")
        ],
        selectedSampleID: selectedID
    )
    let data = try JSONEncoder().encode(document)
    let decoded = try JSONDecoder().decode(GrammarWorkbenchDocument.self, from: data)
    #expect(decoded.source == document.source)
    #expect(decoded.algorithm == "Canonical LR(1)")
    #expect(decoded.samples == document.samples)
    #expect(decoded.selectedSampleID == selectedID)
    #expect(decoded.tests == document.tests)
}

@Test func documentNormalizesMissingSamplesAndSelection() {
    let document = GrammarWorkbenchDocument(
        source: "",
        samples: [],
        selectedSampleID: UUID()
    )
    #expect(document.samples.count == 1)
    #expect(document.selectedSampleID == document.samples[0].id)
}

@Test func documentReadsUTF8PlainTextGrammar() throws {
    let source = "%start S\nS : 'text' ;"
    let document = try GrammarWorkbenchDocument(
        fileData: Data(source.utf8),
        contentType: UTType.plainText
    )

    #expect(document.source == source)
    #expect(document.samples.count == 1)
}

@MainActor
@Test func debouncedEditingRegeneratesOnlyTheLatestValidSource() async throws {
    let store = ExplorerStore()
    let first = "%start S\nS : 'first' ;"
    let second = "%start S\nS : 'second' ;"
    store.updateSource(first, debounceNanoseconds: 30_000_000)
    store.updateSource(second, debounceNanoseconds: 30_000_000)
    try await awaitRegeneration(store)
    #expect(store.frontEnd.source == second)
    #expect(store.artifact.grammarSource == second)
    #expect(store.artifact.terminals.contains("second"))
    #expect(!store.isRegenerating)
}

@MainActor
@Test func invalidEditKeepsLastValidArtifact() async throws {
    let store = ExplorerStore()
    let validSource = store.artifact.grammarSource
    store.updateSource("Broken 'token' ;", debounceNanoseconds: 10_000_000)
    try await awaitRegeneration(store)
    #expect(store.frontEnd.hasErrors)
    #expect(store.artifact.grammarSource == validSource)
}
