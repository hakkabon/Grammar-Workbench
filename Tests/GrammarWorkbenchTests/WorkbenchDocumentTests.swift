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

@MainActor
private func awaitIncrementalSample(_ store: ExplorerStore, text: String) async throws {
    for _ in 0..<200 {
        if store.incrementalSampleAnalysis?.text.text == text { return }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    Issue.record("Incremental sample analysis did not settle within two seconds.")
}

@Test func documentRoundTripPreservesWorkbenchState() throws {
    let selectedID = UUID()
    let document = GrammarWorkbenchDocument(
        source: "%start S\nS : 'value' ;",
        algorithm: "Canonical LR(1)",
        notation: .workbench,
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
    #expect(decoded.notation == .workbench)
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
    #expect(document.notation == .workbench)
    #expect(document.samples.count == 1)
}

@Test func documentDetectsEBNFInImportedPlainText() throws {
    let source = "lexical { NUMBER = /[0-9]+/ ; }\nvalue = NUMBER ;"
    let document = try GrammarWorkbenchDocument(
        fileData: Data(source.utf8),
        contentType: UTType.plainText
    )

    #expect(document.notation == .ebnf)
}

@Test func documentRecognizesEBNFContentType() throws {
    let source = "value = [ \"optional\" ] ;"
    let document = try GrammarWorkbenchDocument(
        fileData: Data(source.utf8),
        contentType: UTType.ebnfGrammar
    )

    #expect(document.source == source)
    #expect(document.notation == .ebnf)
}

@Test func documentRecognizesBNFAndYaccContentTypes() throws {
    let bnf = try GrammarWorkbenchDocument(
        fileData: Data("value ::= \"text\" ;".utf8), contentType: .bnfGrammar
    )
    let yacc = try GrammarWorkbenchDocument(
        fileData: Data("%start S\nS : 'text' ;".utf8), contentType: .yaccGrammar
    )

    #expect(bnf.notation == .ebnf)
    #expect(yacc.notation == .workbench)
    #expect(GrammarWorkbenchDocument.readableContentTypes.contains(.plainText))
    #expect(GrammarWorkbenchDocument.readableContentTypes.contains(.bnfGrammar))
    #expect(GrammarWorkbenchDocument.readableContentTypes.contains(.ebnfGrammar))
    #expect(GrammarWorkbenchDocument.readableContentTypes.contains(.yaccGrammar))
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

@MainActor
@Test func nativeWorkbenchUsesSharedIncrementalSampleAnalysis() async throws {
    let grammar = "%token ID /[a-z]+/\n%skip /\\s+/\n%start S\nS : ID ;"
    let store = ExplorerStore(source: grammar, sampleInput: "first")
    try await awaitIncrementalSample(store, text: "first")
    let firstID = store.incrementalSampleAnalysis?.tokens.first?.id

    store.sampleInput = "second"
    store.parseSample()
    try await awaitIncrementalSample(store, text: "second")

    #expect(store.incrementalSampleAnalysis?.parse.status == .accepted)
    #expect(store.incrementalSampleAnalysis?.reuse.createdTokens == 1)
    #expect(store.incrementalSampleAnalysis?.tokens.first?.id != firstID)
}
