import Foundation

public enum GrammarSelectedResearchCategory: String, CaseIterable, Codable, Sendable {
    case ambiguityGrowth
    case precedence
    case reproducibility
}

public struct GrammarSelectedResearchStudy: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let category: GrammarSelectedResearchCategory
    public let title: String
    public let question: String
    public let context: String
    public let programme: GrammarResearchProgramme

    public init(
        id: String,
        category: GrammarSelectedResearchCategory,
        title: String,
        question: String,
        context: String,
        programme: GrammarResearchProgramme
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.question = question
        self.context = context
        self.programme = programme
    }
}

public struct GrammarSelectedResearchObservation: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let title: String
    public let value: String
    public let explanation: String
    public let passed: Bool
}

public struct GrammarSelectedResearchPreview: Hashable, Codable, Sendable {
    public let studyID: String
    public let title: String
    public let question: String
    public let passed: Bool
    public let conclusion: String
    public let observations: [GrammarSelectedResearchObservation]
    public let limitations: [String]
    public let report: GrammarResearchReport
}

public enum GrammarSelectedResearchPreviewError: Error, LocalizedError, Sendable {
    case unknownStudy(String)

    public var errorDescription: String? {
        switch self {
        case .unknownStudy(let id): "Unknown selected research study ‘\(id)’."
        }
    }
}

public enum GrammarSelectedResearchCatalog {
    public static let studies: [GrammarSelectedResearchStudy] = [
        ambiguityGrowth,
        precedence,
        reproducibility
    ]

    public static func study(id: String) -> GrammarSelectedResearchStudy? {
        studies.first { $0.id == id }
    }

    public static let ambiguityGrowth = GrammarSelectedResearchStudy(
        id: "ambiguity-growth", category: .ambiguityGrowth,
        title: "How quickly does ambiguity grow?",
        question: "Does an expression grammar retain the expected two and five derivations for three and four operands?",
        context: "The grammar has no precedence rule, so every binary grouping remains meaningful. The expected counts are the first non-trivial Catalan values.",
        programme: .init(
            id: "org.grammar-workbench.preview.ambiguity-growth",
            title: "Selected preview: ambiguity growth",
            rationale: "Demonstrate compact preservation of small Catalan ambiguity.",
            repetitions: 3,
            cases: [
                ambiguityCase(id: "three-operands", input: "id + id + id", derivations: 2),
                ambiguityCase(id: "four-operands", input: "id + id + id + id", derivations: 5)
            ]
        )
    )

    public static let precedence = GrammarSelectedResearchStudy(
        id: "precedence-hidden-ambiguity", category: .precedence,
        title: "What does precedence hide?",
        question: "Can production parsing stay deterministic while research mode exposes the alternatives suppressed by associativity?",
        context: "A left-associative declaration selects one production parse. Research exploration can include the suppressed candidate without changing production behavior.",
        programme: .init(
            id: "org.grammar-workbench.preview.precedence",
            title: "Selected preview: precedence-hidden ambiguity",
            rationale: "Separate production conflict resolution from the underlying ambiguous grammar.",
            repetitions: 3,
            cases: [.init(
                id: "left-associative-plus", name: "Left-associative addition",
                hypothesis: "Deterministic parsing accepts one choice while generalized research retains two derivations.",
                grammar: .init(source: "%start E\n%left '+'\nE : E '+' E | 'id' ;"),
                input: "id + id + id",
                generalizedOptions: .init(maximumTrees: 16, exploresResolvedConflicts: true),
                expectation: .init(
                    deterministicStatus: .accepted, generalizedStatus: .ambiguous,
                    minimumDerivations: 2, maximumDerivations: 2
                )
            )]
        )
    )

    public static let reproducibility = GrammarSelectedResearchStudy(
        id: "search-reproducibility", category: .reproducibility,
        title: "Does search order change the answer?",
        question: "Do repeated depth-first runs and breadth-first exploration produce the same forest evidence?",
        context: "Traversal order may affect discovery order, but it must not change which derivations the shared forest represents.",
        programme: .init(
            id: "org.grammar-workbench.preview.reproducibility",
            title: "Selected preview: search reproducibility",
            rationale: "Check repeated identities and search-strategy invariance.",
            repetitions: 5,
            cases: [ambiguityCase(
                id: "five-repeated-runs", input: "id + id + id + id", derivations: 5
            )]
        )
    )

    private static func ambiguityCase(
        id: String, input: String, derivations: Int
    ) -> GrammarResearchCase {
        .init(
            id: id, name: "\(derivations) represented derivations",
            hypothesis: "The shared forest represents exactly \(derivations) derivations, independently of search order.",
            grammar: .init(source: "%start E\nE : E '+' E | 'id' ;"),
            input: input,
            generalizedOptions: .init(maximumTrees: 16),
            expectation: .init(
                deterministicStatus: .conflict, generalizedStatus: .ambiguous,
                minimumDerivations: derivations, maximumDerivations: derivations
            )
        )
    }
}

public enum GrammarSelectedResearchPreviewEngine {
    public static func run(studyID: String) throws -> GrammarSelectedResearchPreview {
        guard let study = GrammarSelectedResearchCatalog.study(id: studyID) else {
            throw GrammarSelectedResearchPreviewError.unknownStudy(studyID)
        }
        return try run(study)
    }

    public static func run(
        _ study: GrammarSelectedResearchStudy
    ) throws -> GrammarSelectedResearchPreview {
        let report = try GrammarResearchValidator.run(study.programme)
        var observations: [GrammarSelectedResearchObservation] = []
        for result in report.cases {
            observations.append(.init(
                id: "\(result.id)-outcome", title: result.name,
                value: result.passed ? "Matches the hypothesis" : "Hypothesis falsified",
                explanation: result.passed
                    ? outcomeExplanation(result)
                    : result.failures.joined(separator: " "),
                passed: result.passed
            ))
            observations.append(.init(
                id: "\(result.id)-forest", title: "Represented derivations",
                value: String(result.derivationCount),
                explanation: "The count comes from the shared-packed forest, not only the materialized tree preview.",
                passed: result.passed
            ))
        }
        let invariant = report.cases.allSatisfy { $0.searchStrategiesAgree && $0.repetitionsStable }
        observations.append(.init(
            id: "reproducibility", title: "Reproducibility",
            value: invariant ? "Stable" : "Changed between runs",
            explanation: invariant
                ? "Repeated runs and both search strategies produced the same evidence identities."
                : "At least one repeat or search strategy produced different evidence.",
            passed: invariant
        ))
        return .init(
            studyID: study.id, title: study.title, question: study.question,
            passed: report.passed && invariant,
            conclusion: conclusion(study.category, report: report, invariant: invariant),
            observations: observations,
            limitations: [
                "This preview validates a small, deliberately selected corpus; it is not a proof for every grammar or input.",
                "Timing is recorded in the underlying report but is not used as scientific evidence in this preview.",
                "Resource bounds remain part of every case and a reached bound would falsify these hypotheses."
            ],
            report: report
        )
    }

    private static func outcomeExplanation(_ result: GrammarResearchCaseResult) -> String {
        let deterministic = result.deterministicStatus?.rawValue ?? "not run"
        let generalized = result.generalizedStatus?.rawValue ?? "not run"
        return "Deterministic: \(deterministic). Generalized: \(generalized). Evidence \(result.evidenceFingerprint)."
    }

    private static func conclusion(
        _ category: GrammarSelectedResearchCategory,
        report: GrammarResearchReport,
        invariant: Bool
    ) -> String {
        guard report.passed, invariant else {
            return "The selected evidence does not support the stated hypothesis. Open the observations to see what differed."
        }
        return switch category {
        case .ambiguityGrowth:
            "The shared forest preserves the expected ambiguity growth without making the result depend on traversal order."
        case .precedence:
            "Precedence gives production parsing one deterministic choice while research mode can still reveal the grammar's suppressed alternative."
        case .reproducibility:
            "The represented forest is stable across repeated runs and across depth-first and breadth-first exploration."
        }
    }
}
