import Foundation
import IncrementalParsing
import LanguageTooling
import PL0Language
import Testing
@testable import GrammarWorkbenchSDK

@Suite("Shared language tooling consumer")
struct SharedToolingConsumerTests {
    @Test func projectUsesRealFileURIs() async throws {
        let workspace = GrammarWorkbenchToolingConsumer.makeWorkspace(providers: [PL0Provider()])
        let uri = ToolingDocumentURI("file:///program.pl0")
        let source = IncrementalParsing.SourceSnapshot(
            text: "var x; begin x := 1 end.", revision: .init(1))
        try await workspace.submit(revision: 1, documents: [
            .init(uri: uri, languageID: "pl0", snapshot: source),
        ])
        let definition = try await workspace.definition(
            in: uri, at: .init(line: 0, character: 13))
        #expect(definition.value?.uri == uri.rawValue)
        #expect(definition.analysis?.rebuiltDocuments == [uri])
    }

    @Test func consumesExternalKitThroughSharedDocumentHost() async throws {
        let consumer = GrammarWorkbenchToolingConsumer(provider: PL0Provider())
        let source = "var value; begin value := 1 end."
        let analysis = try await consumer.open(.init(
            text: source, revision: .init(1)))
        let position = SourceLineMap(source).position(
            of: (source as NSString).range(of: "value", options: .backwards).location)
        let definition = try await consumer.definition(at: position)
        let tokens = try await consumer.semanticTokens()

        #expect(consumer.descriptor.id == "pl0")
        #expect(analysis.languageID == "pl0")
        #expect(definition != nil)
        #expect(!tokens.data.isEmpty)
    }
}
