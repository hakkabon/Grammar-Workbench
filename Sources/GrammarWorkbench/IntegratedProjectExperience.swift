import Foundation

public enum GrammarProjectExperienceSeverity: String, Hashable, Codable, Sendable, CaseIterable {
    case error
    case warning
    case information
}

public enum GrammarProjectExperienceArea: String, Hashable, Codable, Sendable, CaseIterable {
    case grammar
    case sources
    case tests
    case semantics
    case generation
}

public enum GrammarProjectExperienceDestination: String, Hashable, Codable, Sendable {
    case editor
    case guide
    case analysis
    case decisions
    case sample
    case tests
    case semantics
    case generation
}

public struct GrammarProjectExperienceItem: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let area: GrammarProjectExperienceArea
    public let title: String
    public let subtitle: String
    public let count: Int
    public let destination: GrammarProjectExperienceDestination

    public init(
        id: String, area: GrammarProjectExperienceArea, title: String, subtitle: String,
        count: Int, destination: GrammarProjectExperienceDestination
    ) {
        self.id = id
        self.area = area
        self.title = title
        self.subtitle = subtitle
        self.count = count
        self.destination = destination
    }
}

public struct GrammarProjectExperienceProblem: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let severity: GrammarProjectExperienceSeverity
    public let area: GrammarProjectExperienceArea
    public let title: String
    public let detail: String
    public let documentID: String?
    public let path: String?
    public let range: SourceRange?
    public let destination: GrammarProjectExperienceDestination

    public init(
        id: String, severity: GrammarProjectExperienceSeverity,
        area: GrammarProjectExperienceArea, title: String, detail: String,
        documentID: String? = nil, path: String? = nil, range: SourceRange? = nil,
        destination: GrammarProjectExperienceDestination
    ) {
        self.id = id
        self.severity = severity
        self.area = area
        self.title = title
        self.detail = detail
        self.documentID = documentID
        self.path = path
        self.range = range
        self.destination = destination
    }
}

public enum GrammarProjectOperationKind: String, Hashable, Codable, Sendable, CaseIterable {
    case compiling
    case comparingAlgorithms
    case analyzingSample
    case exploringAmbiguity
    case bootstrapping
    case previewingResearch
}

public struct GrammarProjectOperation: Identifiable, Hashable, Codable, Sendable {
    public let kind: GrammarProjectOperationKind
    public let title: String
    public let detail: String
    public var id: GrammarProjectOperationKind { kind }

    public init(kind: GrammarProjectOperationKind, title: String, detail: String) {
        self.kind = kind
        self.title = title
        self.detail = detail
    }
}

/// One immutable, UI-neutral view of a language project. A native document can
/// be represented as a one-source project; full project analyses use the same
/// navigator and problem contracts.
public struct GrammarProjectExperienceSnapshot: Hashable, Codable, Sendable {
    public let name: String
    public let healthScore: Int
    public let navigator: [GrammarProjectExperienceItem]
    public let problems: [GrammarProjectExperienceProblem]
    public let operations: [GrammarProjectOperation]
    public let symbolCount: Int
    public let dependencyCount: Int

    public var errorCount: Int { problems.count { $0.severity == .error } }
    public var warningCount: Int { problems.count { $0.severity == .warning } }
    public var isBusy: Bool { !operations.isEmpty }

    public init(
        name: String, healthScore: Int, navigator: [GrammarProjectExperienceItem],
        problems: [GrammarProjectExperienceProblem], operations: [GrammarProjectOperation] = [],
        symbolCount: Int = 0, dependencyCount: Int = 0
    ) {
        self.name = name
        self.healthScore = max(0, min(100, healthScore))
        self.navigator = navigator
        self.problems = Self.sorted(problems)
        self.operations = operations
        self.symbolCount = symbolCount
        self.dependencyCount = dependencyCount
    }

    private static func sorted(
        _ values: [GrammarProjectExperienceProblem]
    ) -> [GrammarProjectExperienceProblem] {
        let rank: [GrammarProjectExperienceSeverity: Int] = [.error: 0, .warning: 1, .information: 2]
        return values.sorted {
            if rank[$0.severity] != rank[$1.severity] {
                return rank[$0.severity, default: 3] < rank[$1.severity, default: 3]
            }
            if $0.path != $1.path { return ($0.path ?? "") < ($1.path ?? "") }
            if $0.range?.start.offset != $1.range?.start.offset {
                return ($0.range?.start.offset ?? Int.max) < ($1.range?.start.offset ?? Int.max)
            }
            return $0.id < $1.id
        }
    }
}

public enum GrammarProjectExperience {
    public static func snapshot(
        name: String,
        compilation: GrammarCompilation,
        samples: [WorkbenchSample],
        tests: [WorkbenchTestCase],
        testReport: WorkbenchTestReport? = nil,
        operations: [GrammarProjectOperation] = []
    ) -> GrammarProjectExperienceSnapshot {
        let guidance = GrammarGuidanceEngine.assess(
            compilation, sampleInput: samples.first?.input,
            testReport: testReport, testCount: tests.count
        )
        var problems = compilation.diagnostics.map { diagnostic in
            GrammarProjectExperienceProblem(
                id: "grammar:\(diagnostic.id)",
                severity: diagnostic.severity == .error ? .error : .warning,
                area: .grammar, title: diagnostic.message,
                detail: "Grammar source, line \(diagnostic.range.start.line), column \(diagnostic.range.start.column)",
                documentID: "grammar", path: name, range: diagnostic.range, destination: .editor
            )
        }
        problems += (compilation.artifact?.decisions ?? []).filter {
            $0.disposition == .unresolved
        }.map { decision in
            .init(
                id: "decision:\(decision.id)", severity: .error, area: .grammar,
                title: decision.title, detail: decision.explanation, destination: .decisions
            )
        }
        if let testReport {
            problems += testReport.results.filter { $0.status != .passed }.map { result in
                .init(
                    id: "test:\(result.id)", severity: .error, area: .tests,
                    title: result.name, detail: result.message, destination: .tests
                )
            }
        }
        let navigator: [GrammarProjectExperienceItem] = [
            .init(
                id: "grammar", area: .grammar, title: "Grammar", subtitle: name,
                count: compilation.grammar?.productions.count ?? 0, destination: .editor
            ),
            .init(
                id: "sources", area: .sources, title: "Examples", subtitle: "Inputs used while developing the grammar",
                count: samples.count, destination: .sample
            ),
            .init(
                id: "tests", area: .tests, title: "Tests", subtitle: "Recorded language behavior",
                count: tests.count, destination: .tests
            ),
            .init(
                id: "semantics", area: .semantics, title: "Semantics", subtitle: "Syntax tree and semantic model",
                count: compilation.grammar?.productions.count ?? 0, destination: .semantics
            ),
            .init(
                id: "generation", area: .generation, title: "Generated outputs", subtitle: "Parser and interchange artifacts",
                count: compilation.succeeded ? 1 : 0, destination: .generation
            )
        ]
        return .init(
            name: name, healthScore: guidance.summary.healthScore,
            navigator: navigator, problems: problems, operations: operations
        )
    }

    public static func snapshot(
        analysis: GrammarProjectAnalysis,
        semantics: GrammarSemanticWorkspaceSnapshot? = nil,
        operations: [GrammarProjectOperation] = []
    ) -> GrammarProjectExperienceSnapshot {
        let manifest = analysis.manifest
        var problems = analysis.compilation.diagnostics.map { diagnostic in
            GrammarProjectExperienceProblem(
                id: "grammar:\(diagnostic.id)",
                severity: diagnostic.severity == .error ? .error : .warning,
                area: .grammar, title: diagnostic.message, detail: "Project grammar",
                documentID: "grammar", path: manifest.name, range: diagnostic.range, destination: .editor
            )
        }
        let paths = Dictionary(uniqueKeysWithValues: manifest.sources.map { ($0.id, $0.path) })
        for document in analysis.documents {
            problems += document.lexing.diagnostics.map { diagnostic in
                .init(
                    id: "lex:\(document.documentID):\(diagnostic.id)", severity: .error,
                    area: .sources, title: diagnostic.message, detail: paths[document.documentID] ?? document.documentID,
                    documentID: document.documentID, path: paths[document.documentID], range: diagnostic.range,
                    destination: .sample
                )
            }
            problems += document.parse.diagnostics.map { diagnostic in
                .init(
                    id: "parse:\(document.documentID):\(diagnostic.id)", severity: .error,
                    area: .sources, title: diagnostic.message, detail: paths[document.documentID] ?? document.documentID,
                    documentID: document.documentID, path: paths[document.documentID], range: diagnostic.range,
                    destination: .sample
                )
            }
        }
        problems += analysis.tests.results.filter { $0.status != .passed }.map {
            .init(
                id: "test:\($0.id)", severity: .error, area: .tests,
                title: $0.name, detail: $0.message, destination: .tests
            )
        }
        if let semantics {
            problems += semantics.diagnostics.map {
                .init(
                    id: "semantic:\($0.id)", severity: .error, area: .semantics,
                    title: $0.message, detail: $0.location.path,
                    documentID: $0.location.documentID, path: $0.location.path,
                    range: $0.location.range, destination: .semantics
                )
            }
        }
        let penalty = problems.reduce(0) { $0 + ($1.severity == .error ? 15 : 4) }
        return .init(
            name: manifest.name, healthScore: 100 - penalty,
            navigator: [
                .init(id: "grammar", area: .grammar, title: "Grammar", subtitle: manifest.name,
                      count: analysis.compilation.grammar?.productions.count ?? 0, destination: .editor),
                .init(id: "sources", area: .sources, title: "Sources", subtitle: "Project documents",
                      count: manifest.sources.count, destination: .sample),
                .init(id: "tests", area: .tests, title: "Tests", subtitle: "Regression suite",
                      count: manifest.tests.count, destination: .tests),
                .init(id: "semantics", area: .semantics, title: "Symbols", subtitle: "Workspace definitions and references",
                      count: semantics?.workspaceSymbols().count ?? 0, destination: .semantics),
                .init(id: "generation", area: .generation, title: "Generated outputs", subtitle: "Configured targets",
                      count: manifest.generators.count, destination: .generation)
            ],
            problems: problems, operations: operations,
            symbolCount: semantics?.workspaceSymbols().count ?? 0,
            dependencyCount: semantics?.dependencies.count ?? 0
        )
    }
}
