import Foundation
import IncrementalParsing
import LanguageTooling
import PL0Language
import Testing
@testable import GrammarWorkbenchSDK

@Suite("Shared language tooling consumer")
struct SharedToolingConsumerTests {
    @Test func projectUsesRealFileURIs() async throws {
        let project = GrammarWorkbenchToolingConsumer.makeProject(providers: [PL0Provider()])
        let uri = ToolingDocumentURI("file:///program.pl0")
        let source = IncrementalParsing.SourceSnapshot(
            text: "var x; begin x := 1 end.", revision: .init(1))
        try await project.update(revision: 1, documents: [(uri, "pl0", source)])
        let definition = try await project.definition(
            in: uri, at: .init(line: 0, character: 13))
        #expect(definition?.uri == uri.rawValue)
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
