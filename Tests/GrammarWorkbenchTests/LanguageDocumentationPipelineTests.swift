import Foundation
import Testing
@testable import GrammarWorkbench

@Suite("Language documentation pipeline")
struct LanguageDocumentationPipelineTests {
    private let source = """
    %start Root
    Root : Item Tail ;
    Item : 'id' | ;
    Tail : ',' Item Tail | ;
    Dead : 'x' ;
    """

    @Test("Manifest captures linked rule facts and stable source identities")
    func manifest() throws {
        let compilation = GrammarWorkbenchAPI.compile(.init(source: source))
        let first = try GrammarLanguageDocumentationPipeline.build(
            from: compilation, title: "Example Language"
        )
        let second = try GrammarLanguageDocumentationPipeline.build(
            from: compilation, title: "Example Language"
        )
        let item = try #require(first.rules.first { $0.id == "Item" })

        #expect(first == second)
        #expect(first.schemaVersion == 1)
        #expect(first.startRule == "Root")
        #expect(item.isNullable)
        #expect(item.incomingRules == ["Root", "Tail"])
        #expect(item.productions.count == 2)
        #expect(item.productions.first?.symbols.first?.kind == .terminal)
        #expect(first.rules.first { $0.id == "Dead" }?.isReachable == false)
        #expect(Set(first.rules.map(\.anchor)).count == first.rules.count)
    }

    @Test("JSON manifest round-trips and rejects incompatible or unresolved data")
    func interchange() throws {
        let document = try GrammarLanguageDocumentationPipeline.build(
            from: GrammarWorkbenchAPI.compile(.init(source: source))
        )
        let encoded = try GrammarLanguageDocumentationPipeline.encode(document)
        #expect(try GrammarLanguageDocumentationPipeline.decode(encoded) == document)
        #expect(String(decoding: encoded, as: UTF8.self).contains("\"schemaVersion\" : 1"))

        let future = GrammarLanguageDocumentation(
            schemaVersion: 99, title: document.title,
            sourceFingerprint: document.sourceFingerprint, startRule: document.startRule,
            terminals: document.terminals, rules: document.rules
        )
        #expect(throws: GrammarLanguageDocumentationError.self) {
            try GrammarLanguageDocumentationPipeline.validate(future)
        }
    }

    @Test("Markdown and HTML are deterministic, linked, escaped, and diagrammed")
    func renderers() throws {
        let document = try GrammarLanguageDocumentationPipeline.build(
            from: GrammarWorkbenchAPI.compile(.init(source: source)),
            title: "Example <Language>"
        )
        let markdown = try GrammarLanguageDocumentationPipeline.renderMarkdown(document)
        let html = try GrammarLanguageDocumentationPipeline.renderHTML(document)

        #expect(markdown.contains("# Example <Language>"))
        #expect(markdown.contains("```text"))
        #expect(markdown.contains("[Item](#rule-4974656d)"))
        #expect(html.contains("<title>Example &lt;Language&gt;</title>"))
        #expect(html.contains("href=\"#rule-4974656d\""))
        #expect(html.contains("<svg"))
        #expect(html.contains("aria-label=\"Railroad diagram for Item\""))
        #expect(try GrammarLanguageDocumentationPipeline.renderHTML(document) == html)
    }

    @Test("Built-in generator supports individual formats and reproducible bundles")
    func generator() async throws {
        let compilation = GrammarWorkbenchAPI.compile(.init(source: source))
        let registry = GrammarGeneratorRegistry()
        #expect(await registry.availableGenerators().contains { $0.id == "language-documentation" })

        let bundle = try await registry.generate(
            identifier: "language-documentation", from: compilation,
            options: .init(["title": "Example", "format": "bundle", "diagrams": "true"])
        )
        #expect(bundle.files.map(\.suggestedFilename) == [
            "LanguageReference.html", "LanguageReference.md", "LanguageReference.json"
        ])
        #expect(bundle.files.allSatisfy { !$0.contents.isEmpty })

        let markdown = try await registry.generate(
            identifier: "language-documentation", from: compilation,
            options: .init(["format": "markdown", "diagrams": "false"])
        )
        #expect(markdown.files.count == 1)
        #expect(markdown.files.first?.text?.contains("```text") == false)
    }
}
