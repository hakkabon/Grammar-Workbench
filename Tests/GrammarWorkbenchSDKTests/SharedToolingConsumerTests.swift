import Foundation
import IncrementalParsing
import LanguageTooling
import PL0Language
import Testing
@testable import GrammarWorkbenchSDK

@Suite("Shared language tooling consumer")
struct SharedToolingConsumerTests {
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
