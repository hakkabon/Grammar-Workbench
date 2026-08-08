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
    }

    let schemaVersion: Int
    let publicAPIVersion: Int
    let minimumMacOSVersion: String
    let requiredConsumerFixtures: [String]
    let requiredProducts: [String]
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
    #expect(GrammarWorkbenchCapabilities.generalizedParsing == .experimental)

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
