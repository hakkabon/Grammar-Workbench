import AppKit
import Foundation
import SwiftUI
import Testing
@testable import GrammarWorkbench

private struct ReleaseCandidatePolicy: Decodable {
    struct Budgets: Decodable {
        let canonicalConstructionMilliseconds: Double
        let canonicalStates: Int
        let canonicalItems: Int
        let canonicalTableEntries: Int
        let artifactJSONBytes: Int
        let repeatedParseMilliseconds: Double
        let repeatedParseCount: Int
        let generalizedMaximumConfigurations: Int
        let generalizedMaximumSteps: Int
        let generalizedMaximumTrees: Int
        let platformMaximumConcurrentRequests: Int
        let platformBatchRequestCount: Int
        let incrementalMinimumTokenReusePercent: Double
        let incrementalMaximumRelexPercent: Double
        let incrementalMaximumReparsePercent: Double
        let incrementalMinimumSemanticReusePercent: Double
    }

    let schemaVersion: Int
    let publicAPIVersion: Int
    let minimumMacOSVersion: String
    let requiredConsumerFixtures: [String]
    let requiredProducts: [String]
    let requiredProjectManifests: [String]
    let budgets: Budgets
}

private func packageRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func releaseCandidatePolicy() throws -> ReleaseCandidatePolicy {
    let url = packageRoot().appendingPathComponent("Packaging/ReleaseCandidate.json")
    return try JSONDecoder().decode(ReleaseCandidatePolicy.self, from: Data(contentsOf: url))
}

@Test func releaseCandidatePolicyMatchesPublicContracts() throws {
    let policy = try releaseCandidatePolicy()
    #expect(policy.schemaVersion == 1)
    #expect(policy.publicAPIVersion == GrammarWorkbenchAPI.version)
    #expect(policy.minimumMacOSVersion == "14.0")
    #expect(GrammarWorkbenchCapabilities.deterministicParsing == .stable)
    #expect(GrammarWorkbenchCapabilities.semanticOutput == .stable)
    #expect(GrammarWorkbenchCapabilities.generatorEcosystem == .stable)
    #expect(GrammarWorkbenchCapabilities.languageServer == .stable)
    #expect(GrammarWorkbenchCapabilities.generalizedParsing == .stable)
    #expect(GrammarWorkbenchCapabilities.incrementalLanguageInfrastructure == .stable)
    #expect(GrammarWorkbenchCapabilities.projectInfrastructure == .stable)
    #expect(GrammarWorkbenchCapabilities.advancedParsingPlatform == .stable)
    #expect(GrammarWorkbenchCapabilities.guidedGrammarEngineering == .stable)

    for fixture in policy.requiredConsumerFixtures {
        let manifest = packageRoot()
            .appendingPathComponent("Validation/Consumers")
            .appendingPathComponent(fixture)
            .appendingPathComponent("Package.swift")
        #expect(FileManager.default.fileExists(atPath: manifest.path))
    }
    let manifest = try String(contentsOf: packageRoot().appendingPathComponent("Package.swift"))
    for product in policy.requiredProducts {
        #expect(manifest.contains("name: \"\(product)\""))
    }
    for path in policy.requiredProjectManifests {
        let data = try Data(contentsOf: packageRoot().appendingPathComponent(path))
        #expect(try GrammarProjectCodec.decode(data).kind == GrammarProjectManifest.kindIdentifier)
    }
}

@Test func incrementalLanguageSessionMeetsDeclaredReuseBudget() async throws {
    let budget = try releaseCandidatePolicy().budgets
    let grammar = "%token ID /[a-z]+/\n%skip /\\s+/\n%start List\nList : List ',' ID | ID ;"
    let compilation = GrammarWorkbenchAPI.compile(.init(source: grammar))
    let session = try GrammarIncrementalLanguageSession(compilation: compilation)
    let opened = try await session.openDocument(
        id: "budget", text: "one, two, three, four, five", revision: 1
    )
    let evaluator = try GrammarIncrementalSemanticEvaluator(
        compilation: compilation, reducer: IncrementalListSemanticsForReleaseGate()
    )
    _ = try await evaluator.evaluate(opened)
    let changed = try await session.apply(
        documentID: "budget",
        edits: [.init(
            range: .init(
                start: .init(line: 0, utf16Column: 23),
                end: .init(line: 0, utf16Column: 27)
            ),
            replacement: "six"
        )],
        revision: 2
    )
    let reusePercent = Double(changed.reuse.reusedTokens) / Double(opened.tokens.count) * 100
    let relexPercent = Double(changed.incrementalLexing.relexedUTF16Length)
        / Double(changed.text.text.utf16.count) * 100
    let reparsePercent = Double(changed.incrementalParsing.reparsedTokenCount)
        / Double(changed.lexing.tokens.count) * 100
    let semantic = try await evaluator.evaluate(changed)
    let semanticReusePercent = Double(semantic.metrics.reusedValues)
        / Double(changed.semanticIndex.entries.count) * 100

    #expect(changed.parse.status == .accepted)
    #expect(reusePercent >= budget.incrementalMinimumTokenReusePercent)
    #expect(changed.incrementalLexing.strategy == .incremental)
    #expect(relexPercent <= budget.incrementalMaximumRelexPercent)
    #expect(changed.incrementalParsing.strategy == .incremental)
    #expect(reparsePercent <= budget.incrementalMaximumReparsePercent)
    #expect(semanticReusePercent >= budget.incrementalMinimumSemanticReusePercent)
}

private struct IncrementalListSemanticsForReleaseGate: GrammarSemanticReducer {
    func terminal(_ token: GrammarInputTokenSnapshot, node: GrammarSyntaxNode) -> Int { 1 }
    func missing(symbol: String, node: GrammarSyntaxNode) -> Int { 0 }
    func reduce(
        production: GrammarProductionSnapshot, children: [Int], node: GrammarSyntaxNode
    ) -> Int { children.reduce(0, +) }
}

@Test func generalizedParsingStaysWithinDeclaredReleaseBudgets() throws {
    let budget = try releaseCandidatePolicy().budgets
    let grammar = "%start E\nE : E '+' E | 'id' ;"
    let result = GrammarWorkbenchAPI.compile(.init(source: grammar)).parseGeneralized(
        "id + id + id + id",
        options: .init(
            maximumConfigurations: budget.generalizedMaximumConfigurations,
            maximumSteps: budget.generalizedMaximumSteps,
            maximumTrees: budget.generalizedMaximumTrees
        )
    )

    #expect(result.status == .ambiguous)
    #expect(!result.wasTruncated)
    #expect(result.alternatives.count == 5)
    #expect(result.metrics.exploredConfigurations <= budget.generalizedMaximumSteps)
}

@Test func advancedParsingPlatformStaysWithinDeclaredReleaseBudgets() async throws {
    let budget = try releaseCandidatePolicy().budgets
    let compilation = GrammarWorkbenchAPI.compile(.init(
        source: "%start E\nE : E '+' E | 'id' ;"
    ))
    let platform = try GrammarParsingPlatform(compilation: compilation)
    let requests = (0..<budget.platformBatchRequestCount).map {
        GrammarPlatformParseRequest(
            id: "platform-\($0)",
            input: "id + id + id",
            options: .init(ambiguitySelection: .firstStable)
        )
    }
    let result = await platform.parseBatch(
        requests,
        options: .init(maximumConcurrentRequests: budget.platformMaximumConcurrentRequests)
    )

    #expect(result.results.map(\.id) == requests.map(\.id))
    #expect(result.accepted == requests.count)
    #expect(result.metrics.maximumConcurrentRequests == budget.platformMaximumConcurrentRequests)
    #expect(result.results.allSatisfy {
        $0.metrics.generalizedConfigurations <= budget.generalizedMaximumSteps
    })
}

@Test func representativeGrammarStaysWithinDeclaredReleaseBudgets() throws {
    let budget = try releaseCandidatePolicy().budgets
    let alternatives = (0..<160).map { "Rule\($0)" }.joined(separator: " | ")
    let rules = (0..<160).map { "Rule\($0) : 'token\($0)' ;" }.joined(separator: "\n")
    let source = "%start Root\nRoot : \(alternatives) ;\n\(rules)"
    let compilation = GrammarWorkbenchAPI.compile(.init(source: source, algorithm: .canonical))

    #expect(compilation.succeeded)
    #expect(compilation.performance.totalMilliseconds < budget.canonicalConstructionMilliseconds)
    #expect(compilation.performance.stateCount < budget.canonicalStates)
    #expect(compilation.performance.itemCount < budget.canonicalItems)
    #expect(compilation.performance.tableEntryCount < budget.canonicalTableEntries)
    #expect(try compilation.encodeArtifactSnapshot().count < budget.artifactJSONBytes)
}

@Test func repeatedDeterministicParsingStaysWithinDeclaredReleaseBudget() throws {
    let budget = try releaseCandidatePolicy().budgets
    let grammar = "%token ID /[a-z]+/\n%skip /\\s+/\n%start List\nList : List ',' ID | ID ;"
    let compilation = GrammarWorkbenchAPI.compile(.init(source: grammar))
    let start = Date()
    for _ in 0..<budget.repeatedParseCount {
        #expect(compilation.parse("one, two, three", options: .init(enablesRecovery: false)).status == .accepted)
    }
    #expect(Date().timeIntervalSince(start) * 1_000 < budget.repeatedParseMilliseconds)
}

@MainActor
@Test func longGrammarLinesRemainContainedByTheEditorClipView() {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
    scrollView.hasHorizontalScroller = true
    let textView = GrammarSourceEditor.makeTextView(contentSize: scrollView.contentSize)
    textView.string = "%token LONG /" + String(repeating: "[A-Za-z0-9]", count: 200) + "/"
    scrollView.documentView = textView
    textView.sizeToFit()
    scrollView.layoutSubtreeIfNeeded()

    #expect(scrollView.contentView.bounds.width <= 320)
    #expect(textView.frame.width > scrollView.contentView.bounds.width)
    #expect(scrollView.hasHorizontalScroller)
    #expect(scrollView.contentView.superview === scrollView)
}
