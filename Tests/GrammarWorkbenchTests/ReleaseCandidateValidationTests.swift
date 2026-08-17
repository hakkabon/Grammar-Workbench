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
        let generalizedMaximumForestNodes: Int
        let generalizedMaximumPackedFamilies: Int
        let generalizedScalabilityMaximumNodes: Int
        let generalizedScalabilityMaximumFamilies: Int
        let platformMaximumConcurrentRequests: Int
        let platformBatchRequestCount: Int
        let transformationMaximumGeneratedInputs: Int
        let transformationMaximumGeneratedCandidates: Int
        let transformationMaximumDerivationSteps: Int
        let incrementalMinimumTokenReusePercent: Double
        let incrementalMaximumRelexPercent: Double
        let incrementalMaximumReparsePercent: Double
        let incrementalMinimumSemanticReusePercent: Double
        let bootstrapMaximumGenerations: Int
        let bootstrapMinimumCorpusCases: Int
        let semanticWorkspaceMaximumOccurrences: Int
        let semanticWorkspaceMaximumDependencies: Int
        let integratedProjectMaximumProblems: Int
        let integratedProjectNavigatorItems: Int
        let statefulToolingMaximumSessions: Int
        let statefulToolingMaximumDocumentsPerSession: Int
        let semanticLanguageKitMaximumProductions: Int
        let semanticLanguageKitMaximumRules: Int
        let semanticLanguageKitMaximumTests: Int
        let graphVisualizationMaximumNodes: Int
        let graphVisualizationMaximumEdges: Int
        let graphVisualizationMaximumMilliseconds: Double
    }

    let schemaVersion: Int
    let publicAPIVersion: Int
    let minimumMacOSVersion: String
    let requiredConsumerFixtures: [String]
    let requiredProducts: [String]
    let requiredProjectManifests: [String]
    let requiredSemanticLanguageKits: [String]
    let requiredGraphFixtures: [String]
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
    #expect(GrammarWorkbenchCapabilities.grammarAnalysisAndTransformation == .stable)
    #expect(GrammarWorkbenchCapabilities.bootstrapLaboratory == .stable)
    #expect(GrammarWorkbenchCapabilities.sharedForestsAndScalableGeneralizedParsing == .stable)
    #expect(GrammarWorkbenchCapabilities.semanticWorkspaceServices == .stable)
    #expect(GrammarWorkbenchCapabilities.languageToolingSDKAndPortability == .stable)
    #expect(GrammarWorkbenchCapabilities.integratedLanguageProjectExperience == .stable)
    #expect(GrammarWorkbenchCapabilities.statefulToolingProtocolAndServiceHost == .stable)
    #expect(GrammarWorkbenchCapabilities.semanticLanguageKits == .stable)
    #expect(GrammarWorkbenchCapabilities.graphVisualizationPlatform == .stable)
    #expect(GrammarWorkbenchCapabilities.crossPlatformCoreSeparation == .stable)

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
    for path in policy.requiredSemanticLanguageKits {
        let data = try Data(contentsOf: packageRoot().appendingPathComponent(path))
        let kit = try GrammarSemanticLanguageKitCodec.decode(data, requirePassingTests: true)
        #expect(kit.manifest.kind == GrammarSemanticLanguageKitManifest.kindIdentifier)
    }
    for path in policy.requiredGraphFixtures {
        let data = try Data(contentsOf: packageRoot().appendingPathComponent(path))
        _ = try JSONDecoder().decode(GrammarGraph.self, from: data)
    }
}

@Test func graphVisualizationStaysWithinReleaseBudgets() throws {
    let policy = try releaseCandidatePolicy()
    let path = try #require(policy.requiredGraphFixtures.first)
    let graph = try JSONDecoder().decode(
        GrammarGraph.self,
        from: Data(contentsOf: packageRoot().appendingPathComponent(path))
    )
    let layout = try GrammarGraphLayoutEngine.layout(graph)
    #expect(layout.nodes.count <= policy.budgets.graphVisualizationMaximumNodes)
    #expect(layout.routes.count <= policy.budgets.graphVisualizationMaximumEdges)
    #expect(layout.metrics.durationMilliseconds <= policy.budgets.graphVisualizationMaximumMilliseconds)
    #expect(layout.nodes.count == graph.nodes.count)
    #expect(layout.routes.count == graph.edges.count)
}

@Test func semanticLanguageKitStaysWithinReleaseBudgets() throws {
    let policy = try releaseCandidatePolicy()
    let data = try Data(contentsOf: packageRoot().appendingPathComponent(
        try #require(policy.requiredSemanticLanguageKits.first)
    ))
    let kit = try GrammarSemanticLanguageKitCodec.decode(data, requirePassingTests: true)
    #expect(kit.semanticModel.productions.count <= policy.budgets.semanticLanguageKitMaximumProductions)
    #expect(kit.manifest.semantics.rules.count <= policy.budgets.semanticLanguageKitMaximumRules)
    #expect(kit.manifest.tests.count <= policy.budgets.semanticLanguageKitMaximumTests)
    #expect(kit.isConformant)
}

@Test func semanticWorkspaceServicesStayWithinReleaseBudgets() async throws {
    let budget = try releaseCandidatePolicy().budgets
    let grammar = #"""
    %token LET /let\b/
    %token USE /use\b/
    %token ID /[A-Za-z_][A-Za-z0-9_]*/
    %token SEMI /;/
    %skip /\s+/
    %start Program
    Program : Program Statement | Statement ;
    Statement : LET ID SEMI | USE ID SEMI ;
    """#
    let project = GrammarProjectManifest(
        name: "Release semantic workspace", grammar: .init(source: grammar),
        sources: [
            .init(id: "definitions", path: "Definitions.lang", text: "let alpha;", revision: 1),
            .init(id: "uses", path: "Uses.lang", text: "use alpha;", revision: 1)
        ]
    )
    let workspace = try GrammarProjectWorkspace(manifest: project)
    let analysis = try await workspace.analyze()
    let model = try GrammarSemanticModel(compilation: analysis.compilation)
    let definition = try #require(model.productions(lhs: "Statement", rhs: ["LET", "ID", "SEMI"]).first)
    let reference = try #require(model.productions(lhs: "Statement", rhs: ["USE", "ID", "SEMI"]).first)
    let services = analysis.semanticWorkspace(schema: .init(rules: [
        .init(tokenKind: "ID", enclosingProduction: definition.id, kind: "variable", role: .definition),
        .init(tokenKind: "ID", enclosingProduction: reference.id, kind: "variable", role: .reference)
    ]))
    #expect(services.diagnostics.isEmpty)
    #expect(services.occurrences.count <= budget.semanticWorkspaceMaximumOccurrences)
    #expect(services.dependencies.count <= budget.semanticWorkspaceMaximumDependencies)
    #expect(services.workspaceSymbols().count == 1)
    let experience = GrammarProjectExperience.snapshot(analysis: analysis, semantics: services)
    #expect(experience.problems.count <= budget.integratedProjectMaximumProblems)
    #expect(experience.navigator.count == budget.integratedProjectNavigatorItems)
}

@Test func bootstrapLaboratoryRemainsBoundedAndDifferentiallyValidated() throws {
    let budget = try releaseCandidatePolicy().budgets
    let report = try GrammarBootstrapLaboratory.run(
        options: .init(maximumGenerations: budget.bootstrapMaximumGenerations)
    )
    #expect(report.succeeded)
    #expect(report.generations.count <= budget.bootstrapMaximumGenerations)
    #expect(report.corpus.count >= budget.bootstrapMinimumCorpusCases)
    #expect(report.corpus.allSatisfy { $0.matches })
}

@Test func grammarTransformationRemainsExplainableAndBehaviorChecked() throws {
    let budget = try releaseCandidatePolicy().budgets
    let source = "%start S\nS : 'ok' | 'other' ;\nDead : 'unused' ;"
    let request = GrammarCompilationRequest(source: source)
    let compilation = GrammarWorkbenchAPI.compile(request)
    let plan = try GrammarEngineering.plan(.removeUnreachableProductions, for: compilation)
    let result = try GrammarEngineering.execute(
        plan,
        request: request,
        corpus: [.init(input: "ok", origin: "release")],
        tests: [.init(name: "accept", input: "ok", expectation: .accept)],
        options: .init(
            maximumGeneratedInputs: budget.transformationMaximumGeneratedInputs,
            maximumGeneratedCandidates: budget.transformationMaximumGeneratedCandidates,
            maximumDerivationSteps: budget.transformationMaximumDerivationSteps
        )
    )

    #expect(plan.operations.allSatisfy { !$0.reason.isEmpty })
    #expect(result.isSafeToApply)
    #expect(result.behavior.generatedInputs <= budget.transformationMaximumGeneratedInputs)
    #expect(result.testsAfter?.allPassed == true)
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
            maximumTrees: budget.generalizedMaximumTrees,
            maximumForestNodes: budget.generalizedMaximumForestNodes,
            maximumPackedFamilies: budget.generalizedMaximumPackedFamilies
        )
    )

    #expect(result.status == .ambiguous)
    #expect(!result.wasTruncated)
    #expect(result.alternatives.count == 5)
    #expect(result.metrics.exploredConfigurations <= budget.generalizedMaximumSteps)
}

@Test func sharedForestStaysCompactForHighlyAmbiguousInput() throws {
    let budget = try releaseCandidatePolicy().budgets
    let compilation = GrammarWorkbenchAPI.compile(.init(source: "%start S\nS : S S | 'a' ;"))
    let result = compilation.parseGeneralized(
        "a a a a a a a",
        options: .init(
            maximumConfigurations: budget.generalizedMaximumConfigurations,
            maximumSteps: budget.generalizedMaximumSteps,
            maximumTrees: 8,
            maximumForestNodes: budget.generalizedMaximumForestNodes,
            maximumPackedFamilies: budget.generalizedMaximumPackedFamilies
        )
    )
    #expect(result.sharedForest.derivationCount(upTo: 1_000) == 132)
    #expect(result.sharedForest.nodes.count <= budget.generalizedScalabilityMaximumNodes)
    #expect(result.sharedForest.packedFamilyCount <= budget.generalizedScalabilityMaximumFamilies)
    #expect(!result.reachedLimits.contains(.configurations))
    #expect(!result.reachedLimits.contains(.steps))
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
