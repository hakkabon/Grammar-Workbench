import Foundation

public enum GrammarGuidanceSeverity: String, CaseIterable, Codable, Sendable {
    case critical
    case attention
    case opportunity
    case ready
}

public enum GrammarGuidanceDestination: String, Codable, Sendable {
    case editor
    case analysis
    case sample
    case decisions
    case comparison
    case tests
    case research
    case generation
}

public struct GrammarGuidanceFinding: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let severity: GrammarGuidanceSeverity
    public let title: String
    public let explanation: String
    public let action: String
    public let destination: GrammarGuidanceDestination
    public let sourceRange: SourceRange?

    public init(
        id: String,
        severity: GrammarGuidanceSeverity,
        title: String,
        explanation: String,
        action: String,
        destination: GrammarGuidanceDestination,
        sourceRange: SourceRange? = nil
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.explanation = explanation
        self.action = action
        self.destination = destination
        self.sourceRange = sourceRange
    }
}

public struct GrammarGuidanceSummary: Hashable, Codable, Sendable {
    public let healthScore: Int
    public let errors: Int
    public let warnings: Int
    public let unresolvedConflicts: Int
    public let resolvedDecisions: Int
    public let passingTests: Int
    public let failingTests: Int

    public var headline: String {
        if errors > 0 { return "The grammar needs corrections before it can be used." }
        if unresolvedConflicts > 0 { return "The grammar compiles, but parsing decisions still need attention." }
        if warnings > 0 || failingTests > 0 { return "The grammar works, with opportunities to improve its reliability." }
        return "The grammar is healthy and ready for parser generation."
    }
}

public struct GrammarGuidanceReport: Hashable, Codable, Sendable {
    public let summary: GrammarGuidanceSummary
    public let findings: [GrammarGuidanceFinding]

    public var nextAction: GrammarGuidanceFinding? { findings.first }
}

public struct GrammarGuidanceExample: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let input: String

    public init(id: String = UUID().uuidString, name: String, input: String) {
        self.id = id
        self.name = name
        self.input = input
    }
}

public enum GrammarGuidedTransformation: String, CaseIterable, Codable, Sendable {
    case removeDuplicateProductionLines
    case removeUnreachableProductionLines
    case removeUnproductiveProductionLines

    public var title: String {
        switch self {
        case .removeDuplicateProductionLines: "Remove duplicate production lines"
        case .removeUnreachableProductionLines: "Remove unreachable production lines"
        case .removeUnproductiveProductionLines: "Remove unproductive production lines"
        }
    }
}

public struct GrammarGuidedExampleComparison: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let before: GrammarParseStatus
    public let after: GrammarParseStatus
    public var changed: Bool { before != after }
    public var regressed: Bool {
        let accepted: Set<GrammarParseStatus> = [.accepted, .acceptedWithRecovery]
        return accepted.contains(before) && !accepted.contains(after)
    }
}

public struct GrammarGuidedTransformationPreview: Sendable {
    public let transformation: GrammarGuidedTransformation
    public let originalSource: String
    public let proposedSource: String
    public let removedLines: [Int]
    public let diagnostics: [GrammarDiagnostic]
    public let artifactDiff: GrammarArtifactDiff?
    public let examples: [GrammarGuidedExampleComparison]
    public let testsBefore: WorkbenchTestReport?
    public let testsAfter: WorkbenchTestReport?
    public let plan: GrammarTransformationPlan?
    public let behavior: GrammarBehaviorComparison?

    public var hasChanges: Bool { originalSource != proposedSource }
    public var changedExamples: [GrammarGuidedExampleComparison] { examples.filter(\.changed) }
    public var regressedExamples: [GrammarGuidedExampleComparison] { examples.filter(\.regressed) }
    public var isSafeToApply: Bool {
        guard hasChanges, !diagnostics.contains(where: { $0.severity == .error }), regressedExamples.isEmpty,
              behavior?.agreesOnCorpus != false else {
            return false
        }
        guard let testsAfter else { return true }
        return testsAfter.failed == 0
    }
}

public enum GrammarGuidanceEngine {
    public static func assess(
        _ compilation: GrammarCompilation,
        sampleInput: String? = nil,
        tests: [WorkbenchTestCase] = []
    ) -> GrammarGuidanceReport {
        assess(
            compilation, sampleInput: sampleInput,
            testReport: tests.isEmpty ? nil : compilation.runTests(tests),
            testCount: tests.count
        )
    }

    public static func assess(
        _ compilation: GrammarCompilation,
        sampleInput: String? = nil,
        testReport: WorkbenchTestReport?,
        testCount: Int
    ) -> GrammarGuidanceReport {
        let errors = compilation.diagnostics.filter { $0.severity == .error }
        let warnings = compilation.diagnostics.filter { $0.severity == .warning }
        let unresolved = compilation.artifact?.decisions.filter { $0.disposition == .unresolved } ?? []
        let resolved = compilation.artifact?.decisions.filter { $0.disposition == .resolved } ?? []
        var findings: [GrammarGuidanceFinding] = []

        findings += errors.map { diagnostic in
            .init(
                id: "diagnostic-\(diagnostic.id)", severity: .critical,
                title: plainTitle(for: diagnostic),
                explanation: diagnostic.message,
                action: "Show this problem in the grammar editor", destination: .editor,
                sourceRange: diagnostic.range
            )
        }
        findings += unresolved.map { decision in
            .init(
                id: "decision-\(decision.id)", severity: .attention,
                title: "Choose how ‘\(decision.symbol)’ should be interpreted",
                explanation: decision.explanation,
                action: "Compare the competing interpretations", destination: .decisions
            )
        }
        findings += warnings.map { diagnostic in
            .init(
                id: "warning-\(diagnostic.id)", severity: .attention,
                title: plainTitle(for: diagnostic), explanation: diagnostic.message,
                action: "Review the affected declaration", destination: .editor,
                sourceRange: diagnostic.range
            )
        }
        if let report = testReport, report.failed > 0 {
            findings.append(.init(
                id: "failing-tests", severity: .attention,
                title: "\(report.failed) grammar test\(report.failed == 1 ? "" : "s") need attention",
                explanation: "The grammar's recorded examples no longer all behave as expected.",
                action: "Review the failing tests", destination: .tests
            ))
        }
        if let sampleInput, !sampleInput.isEmpty, compilation.succeeded {
            let sample = compilation.parse(sampleInput)
            if sample.status != .accepted {
                findings.append(.init(
                    id: "sample-\(sample.status.rawValue)", severity: .opportunity,
                    title: sample.status == .acceptedWithRecovery
                        ? "The current example needs recovery" : "The current example is not accepted",
                    explanation: sample.message,
                    action: "Inspect the example and its expected tokens", destination: .sample
                ))
            }
        }
        if compilation.succeeded && testCount == 0 {
            findings.append(.init(
                id: "add-tests", severity: .opportunity,
                title: "Record the language behavior you want to preserve",
                explanation: "Examples make grammar changes safer by checking accepted, rejected, and conflicting inputs.",
                action: "Add a small grammar test suite", destination: .tests
            ))
        } else if compilation.succeeded && testReport == nil {
            findings.append(.init(
                id: "run-tests", severity: .opportunity,
                title: "Run the saved grammar tests",
                explanation: "The project has \(testCount) recorded test\(testCount == 1 ? "" : "s"), but they have not been checked against this build.",
                action: "Run the test suite", destination: .tests
            ))
        }
        if compilation.succeeded && unresolved.isEmpty {
            findings.append(.init(
                id: "ready", severity: .ready,
                title: "Parser construction is ready",
                explanation: resolved.isEmpty
                    ? "The selected LR algorithm constructed a deterministic parser without conflicts."
                    : "All competing parser actions have an explicit precedence or associativity decision.",
                action: "Try an input or generate a parser", destination: .sample
            ))
        }

        let failing = testReport?.failed ?? 0
        let score = max(0, min(100,
            100 - errors.count * 25 - unresolved.count * 15 - warnings.count * 4 - failing * 8
        ))
        let summary = GrammarGuidanceSummary(
            healthScore: score, errors: errors.count, warnings: warnings.count,
            unresolvedConflicts: unresolved.count, resolvedDecisions: resolved.count,
            passingTests: testReport?.passed ?? 0, failingTests: failing
        )
        return .init(summary: summary, findings: findings.sorted(by: guidanceOrder))
    }

    public static func preview(
        _ transformation: GrammarGuidedTransformation,
        request: GrammarCompilationRequest,
        examples: [GrammarGuidanceExample] = [],
        tests: [WorkbenchTestCase] = []
    ) -> GrammarGuidedTransformationPreview {
        let before = GrammarWorkbenchAPI.compile(request)
        let kind: GrammarTransformationKind = switch transformation {
        case .removeDuplicateProductionLines: .removeDuplicateProductions
        case .removeUnreachableProductionLines: .removeUnreachableProductions
        case .removeUnproductiveProductionLines: .removeUnproductiveProductions
        }
        let corpus = examples.map { GrammarBehaviorCorpusEntry(id: $0.id, input: $0.input, origin: "sample") }
        let plan = try? GrammarEngineering.plan(kind, for: before)
        let execution = plan.flatMap {
            try? GrammarEngineering.execute($0, request: request, corpus: corpus, tests: tests)
        }
        let proposed = execution?.proposedSource ?? request.source
        let after = execution?.compilation ?? before
        let lines = Set(plan?.affectedLines ?? [])
        let comparisons = examples.map { example in
            GrammarGuidedExampleComparison(
                id: example.id, name: example.name,
                before: before.parse(example.input).status,
                after: after.parse(example.input).status
            )
        }
        return .init(
            transformation: transformation, originalSource: request.source,
            proposedSource: proposed, removedLines: lines.sorted(), diagnostics: after.diagnostics,
            artifactDiff: execution?.artifactDiff, examples: comparisons,
            testsBefore: execution?.testsBefore,
            testsAfter: execution?.testsAfter,
            plan: plan, behavior: execution?.behavior
        )
    }

    private static func plainTitle(for diagnostic: GrammarDiagnostic) -> String {
        switch diagnostic.code {
        case "unreachable-nonterminal": "Remove or connect an unreachable rule"
        case "unproductive-nonterminal": "Complete a rule that cannot produce input"
        case "duplicate-production": "Remove a duplicate production"
        case "unused-token": "Remove or use an unused token"
        case "nullable-cycle": "Review a cycle that can repeatedly produce nothing"
        case "undefined-symbol", "undefined-ebnf-symbol": "Define a referenced symbol"
        default: diagnostic.severity == .error ? "Correct a grammar error" : "Review a grammar warning"
        }
    }

    private static func guidanceOrder(_ lhs: GrammarGuidanceFinding, _ rhs: GrammarGuidanceFinding) -> Bool {
        let rank: [GrammarGuidanceSeverity: Int] = [.critical: 0, .attention: 1, .opportunity: 2, .ready: 3]
        return rank[lhs.severity, default: 4] == rank[rhs.severity, default: 4]
            ? lhs.id < rhs.id : rank[lhs.severity, default: 4] < rank[rhs.severity, default: 4]
    }
}
