import Foundation

public struct GrammarResearchExpectation: Hashable, Codable, Sendable {
    public var compilationSucceeds: Bool
    public var deterministicStatus: GrammarParseStatus?
    public var generalizedStatus: GrammarGeneralizedParseStatus?
    public var minimumDerivations: Int
    public var maximumDerivations: Int?
    public var reachedLimits: [GrammarGeneralizedLimit]
    public var requiresSearchStrategyInvariance: Bool

    public init(
        compilationSucceeds: Bool = true,
        deterministicStatus: GrammarParseStatus? = nil,
        generalizedStatus: GrammarGeneralizedParseStatus? = nil,
        minimumDerivations: Int = 0,
        maximumDerivations: Int? = nil,
        reachedLimits: [GrammarGeneralizedLimit] = [],
        requiresSearchStrategyInvariance: Bool = true
    ) {
        self.compilationSucceeds = compilationSucceeds
        self.deterministicStatus = deterministicStatus
        self.generalizedStatus = generalizedStatus
        self.minimumDerivations = max(0, minimumDerivations)
        self.maximumDerivations = maximumDerivations.map { max(0, $0) }
        self.reachedLimits = reachedLimits.sorted { $0.rawValue < $1.rawValue }
        self.requiresSearchStrategyInvariance = requiresSearchStrategyInvariance
    }
}

public struct GrammarResearchCase: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let hypothesis: String
    public let grammar: GrammarCompilationRequest
    public let input: String
    public let generalizedOptions: GrammarGeneralizedParseOptions
    public let expectation: GrammarResearchExpectation

    public init(
        id: String,
        name: String,
        hypothesis: String,
        grammar: GrammarCompilationRequest,
        input: String,
        generalizedOptions: GrammarGeneralizedParseOptions = .init(),
        expectation: GrammarResearchExpectation
    ) {
        self.id = id
        self.name = name
        self.hypothesis = hypothesis
        self.grammar = grammar
        self.input = input
        self.generalizedOptions = generalizedOptions
        self.expectation = expectation
    }
}

public struct GrammarResearchProgramme: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1
    public static let kindIdentifier = "grammar-workbench-research-programme"

    public let schemaVersion: Int
    public let kind: String
    public let id: String
    public let title: String
    public let rationale: String
    public let repetitions: Int
    public let cases: [GrammarResearchCase]

    public init(
        id: String,
        title: String,
        rationale: String,
        repetitions: Int = 3,
        cases: [GrammarResearchCase]
    ) {
        schemaVersion = Self.currentSchemaVersion
        kind = Self.kindIdentifier
        self.id = id
        self.title = title
        self.rationale = rationale
        self.repetitions = min(20, max(1, repetitions))
        self.cases = cases
    }
}

public struct GrammarResearchTimingSummary: Hashable, Codable, Sendable {
    public let samples: Int
    public let minimumNanoseconds: UInt64
    public let medianNanoseconds: UInt64
    public let percentile95Nanoseconds: UInt64
    public let maximumNanoseconds: UInt64
}

public struct GrammarResearchCaseResult: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let hypothesis: String
    public let passed: Bool
    public let compilationSucceeded: Bool
    public let deterministicStatus: GrammarParseStatus?
    public let generalizedStatus: GrammarGeneralizedParseStatus?
    public let derivationCount: Int
    public let reachedLimits: [GrammarGeneralizedLimit]
    public let searchStrategiesAgree: Bool
    public let repetitionsStable: Bool
    public let generalizedEvidenceFingerprint: String
    public let evidenceFingerprint: String
    public let timing: GrammarResearchTimingSummary
    public let failures: [String]
}

public struct GrammarResearchEnvironment: Hashable, Codable, Sendable {
    public let grammarWorkbenchVersion: String
    public let apiVersion: Int
    public let platform: String
}

public struct GrammarResearchReport: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1
    public static let kindIdentifier = "grammar-workbench-research-report"

    public let schemaVersion: Int
    public let kind: String
    public let programmeID: String
    public let programmeFingerprint: String
    public let environment: GrammarResearchEnvironment
    public let cases: [GrammarResearchCaseResult]
    public let evidenceFingerprint: String

    public var passed: Bool { !cases.isEmpty && cases.allSatisfy(\.passed) }
    public var passedCases: Int { cases.count(where: \.passed) }
}

public struct GrammarResearchCaseComparison: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let baselinePassed: Bool
    public let candidatePassed: Bool
    public let evidenceChanged: Bool
    public let medianTimingRatio: Double?
    public var regressed: Bool { baselinePassed && !candidatePassed }
    public var improved: Bool { !baselinePassed && candidatePassed }
}

public struct GrammarResearchReportComparison: Hashable, Codable, Sendable {
    public let programmeID: String
    public let compatibleProgramme: Bool
    public let cases: [GrammarResearchCaseComparison]
    public var regressions: [String] { cases.filter(\.regressed).map(\.id) }
    public var improvements: [String] { cases.filter(\.improved).map(\.id) }
    public var evidenceChanges: [String] { cases.filter(\.evidenceChanged).map(\.id) }
}

public enum GrammarResearchValidationError: Error, LocalizedError, Sendable {
    case unsupportedVersion(Int)
    case invalidKind(String)
    case invalidProgramme(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let value): "Unsupported research programme schema version \(value)."
        case .invalidKind(let value): "Unexpected research programme kind ‘\(value)’."
        case .invalidProgramme(let message): "Invalid research programme: \(message)"
        }
    }
}

public enum GrammarResearchProgrammeCodec {
    public static func encode(_ value: GrammarResearchProgramme) throws -> Data {
        try validate(value)
        return try encoder().encode(value)
    }

    public static func decode(_ data: Data) throws -> GrammarResearchProgramme {
        let value = try JSONDecoder().decode(GrammarResearchProgramme.self, from: data)
        try validate(value)
        return value
    }

    public static func encode(_ value: GrammarResearchReport) throws -> Data {
        try validateReport(value)
        return try encoder().encode(value)
    }

    public static func decodeReport(_ data: Data) throws -> GrammarResearchReport {
        let value = try JSONDecoder().decode(GrammarResearchReport.self, from: data)
        guard value.schemaVersion == GrammarResearchReport.currentSchemaVersion else {
            throw GrammarResearchValidationError.unsupportedVersion(value.schemaVersion)
        }
        guard value.kind == GrammarResearchReport.kindIdentifier else {
            throw GrammarResearchValidationError.invalidKind(value.kind)
        }
        try validateReport(value)
        return value
    }

    public static func fingerprint(_ value: GrammarResearchProgramme) throws -> String {
        try validate(value)
        return ResearchFingerprint.make(try canonicalEncoder().encode(value))
    }

    private static func validate(_ value: GrammarResearchProgramme) throws {
        guard value.schemaVersion == GrammarResearchProgramme.currentSchemaVersion else {
            throw GrammarResearchValidationError.unsupportedVersion(value.schemaVersion)
        }
        guard value.kind == GrammarResearchProgramme.kindIdentifier else {
            throw GrammarResearchValidationError.invalidKind(value.kind)
        }
        guard !value.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GrammarResearchValidationError.invalidProgramme("The programme identifier is empty.")
        }
        guard !value.cases.isEmpty else {
            throw GrammarResearchValidationError.invalidProgramme("At least one case is required.")
        }
        var ids: Set<String> = []
        for item in value.cases {
            guard !item.id.isEmpty, ids.insert(item.id).inserted else {
                throw GrammarResearchValidationError.invalidProgramme("Case identifiers must be nonempty and unique.")
            }
            if let maximum = item.expectation.maximumDerivations,
               maximum < item.expectation.minimumDerivations {
                throw GrammarResearchValidationError.invalidProgramme(
                    "Case ‘\(item.id)’ has an inverted derivation range."
                )
            }
        }
    }

    private static func validateReport(_ value: GrammarResearchReport) throws {
        var identifiers: Set<String> = []
        for item in value.cases {
            guard identifiers.insert(item.id).inserted else {
                throw GrammarResearchValidationError.invalidProgramme(
                    "The report contains duplicate case ‘\(item.id)’."
                )
            }
            let expected: String
            if item.compilationSucceeded {
                let evidence = [
                    item.id, item.deterministicStatus?.rawValue ?? "-",
                    item.generalizedStatus?.rawValue ?? "-", String(item.derivationCount),
                    item.reachedLimits.map(\.rawValue).joined(separator: ","),
                    item.generalizedEvidenceFingerprint
                ].joined(separator: "\u{1f}")
                expected = ResearchFingerprint.make(Data(evidence.utf8))
            } else {
                expected = ResearchFingerprint.make(Data("\(item.id):compile:false".utf8))
            }
            guard expected == item.evidenceFingerprint else {
                throw GrammarResearchValidationError.invalidProgramme(
                    "Case ‘\(item.id)’ has a mismatched evidence fingerprint."
                )
            }
        }
        let evidence = value.cases.sorted { $0.id < $1.id }.map {
            "\($0.id):\($0.evidenceFingerprint):\($0.passed)"
        }.joined(separator: "\n")
        guard ResearchFingerprint.make(Data(evidence.utf8)) == value.evidenceFingerprint else {
            throw GrammarResearchValidationError.invalidProgramme(
                "The report aggregate evidence fingerprint is invalid."
            )
        }
    }

    private static func encoder() -> JSONEncoder {
        let value = JSONEncoder()
        value.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return value
    }

    private static func canonicalEncoder() -> JSONEncoder {
        let value = JSONEncoder()
        value.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return value
    }
}

public enum GrammarResearchValidator {
    public static func run(_ programme: GrammarResearchProgramme) throws -> GrammarResearchReport {
        let programmeFingerprint = try GrammarResearchProgrammeCodec.fingerprint(programme)
        let results = programme.cases.map { run($0, repetitions: programme.repetitions) }
        let evidence = results.sorted { $0.id < $1.id }.map {
            "\($0.id):\($0.evidenceFingerprint):\($0.passed)"
        }.joined(separator: "\n")
        return .init(
            schemaVersion: GrammarResearchReport.currentSchemaVersion,
            kind: GrammarResearchReport.kindIdentifier,
            programmeID: programme.id,
            programmeFingerprint: programmeFingerprint,
            environment: .init(
                grammarWorkbenchVersion: GrammarWorkbenchRelease.version,
                apiVersion: GrammarWorkbenchAPIVersion.current,
                platform: platformName
            ),
            cases: results,
            evidenceFingerprint: ResearchFingerprint.make(Data(evidence.utf8))
        )
    }

    public static func compare(
        baseline: GrammarResearchReport,
        candidate: GrammarResearchReport
    ) -> GrammarResearchReportComparison {
        let baselineCases = Dictionary(uniqueKeysWithValues: baseline.cases.map { ($0.id, $0) })
        let candidateCases = Dictionary(uniqueKeysWithValues: candidate.cases.map { ($0.id, $0) })
        let identifiers = Set(baselineCases.keys).union(candidateCases.keys).sorted()
        return .init(
            programmeID: candidate.programmeID,
            compatibleProgramme: baseline.programmeID == candidate.programmeID
                && baseline.programmeFingerprint == candidate.programmeFingerprint,
            cases: identifiers.map { id in
                let old = baselineCases[id]
                let new = candidateCases[id]
                let ratio: Double? = if let before = old?.timing.medianNanoseconds,
                                        let after = new?.timing.medianNanoseconds,
                                        before > 0 {
                    Double(after) / Double(before)
                } else { nil }
                return .init(
                    id: id, baselinePassed: old?.passed ?? false,
                    candidatePassed: new?.passed ?? false,
                    evidenceChanged: old?.evidenceFingerprint != new?.evidenceFingerprint,
                    medianTimingRatio: ratio
                )
            }
        )
    }

    private static func run(
        _ item: GrammarResearchCase, repetitions: Int
    ) -> GrammarResearchCaseResult {
        let compilation = GrammarWorkbenchAPI.compile(item.grammar)
        var failures: [String] = []
        let succeeded = compilation.succeeded
        if succeeded != item.expectation.compilationSucceeds {
            failures.append("Compilation outcome differed from the expectation.")
        }
        guard succeeded else {
            let evidence = ResearchFingerprint.make(Data("\(item.id):compile:\(succeeded)".utf8))
            return .init(
                id: item.id, name: item.name, hypothesis: item.hypothesis,
                passed: failures.isEmpty, compilationSucceeded: false,
                deterministicStatus: nil, generalizedStatus: nil, derivationCount: 0,
                reachedLimits: [], searchStrategiesAgree: false, repetitionsStable: false,
                generalizedEvidenceFingerprint: "",
                evidenceFingerprint: evidence,
                timing: .init(samples: 0, minimumNanoseconds: 0, medianNanoseconds: 0,
                              percentile95Nanoseconds: 0, maximumNanoseconds: 0),
                failures: failures
            )
        }

        let deterministic = compilation.parse(item.input, options: .init(enablesRecovery: false))
        if let expected = item.expectation.deterministicStatus, deterministic.status != expected {
            failures.append("Deterministic status was \(deterministic.status.rawValue), expected \(expected.rawValue).")
        }
        var fingerprints: [String] = []
        var timings: [UInt64] = []
        var primary: GrammarGeneralizedParseResult?
        for _ in 0..<repetitions {
            var options = item.generalizedOptions
            options.searchStrategy = .depthFirst
            let started = DispatchTime.now().uptimeNanoseconds
            let result = compilation.parseGeneralized(item.input, options: options)
            timings.append(DispatchTime.now().uptimeNanoseconds - started)
            primary = primary ?? result
            fingerprints.append(fingerprint(result))
        }
        let generalized = primary!
        var breadthOptions = item.generalizedOptions
        breadthOptions.searchStrategy = .breadthFirst
        let breadth = compilation.parseGeneralized(item.input, options: breadthOptions)
        let strategiesAgree = fingerprint(generalized) == fingerprint(breadth)
        let repetitionsStable = Set(fingerprints).count == 1
        let derivations = generalized.sharedForest.derivationCount(
            upTo: max(item.generalizedOptions.maximumTrees + 1,
                      item.expectation.maximumDerivations.map { $0 + 1 } ?? 0)
        )
        let limits = generalized.reachedLimits.sorted { $0.rawValue < $1.rawValue }

        if let expected = item.expectation.generalizedStatus, generalized.status != expected {
            failures.append("Generalized status was \(generalized.status.rawValue), expected \(expected.rawValue).")
        }
        if derivations < item.expectation.minimumDerivations {
            failures.append("Observed \(derivations) derivations; expected at least \(item.expectation.minimumDerivations).")
        }
        if let maximum = item.expectation.maximumDerivations, derivations > maximum {
            failures.append("Observed \(derivations) derivations; expected at most \(maximum).")
        }
        if limits != item.expectation.reachedLimits {
            failures.append("Reached limits differed from the expectation.")
        }
        if item.expectation.requiresSearchStrategyInvariance && !strategiesAgree {
            failures.append("Depth-first and breadth-first searches produced different evidence.")
        }
        if !repetitionsStable {
            failures.append("Repeated generalized runs produced unstable evidence.")
        }
        let evidence = [
            item.id, deterministic.status.rawValue, generalized.status.rawValue,
            String(derivations), limits.map(\.rawValue).joined(separator: ","), fingerprints[0]
        ].joined(separator: "\u{1f}")
        return .init(
            id: item.id, name: item.name, hypothesis: item.hypothesis,
            passed: failures.isEmpty, compilationSucceeded: true,
            deterministicStatus: deterministic.status, generalizedStatus: generalized.status,
            derivationCount: derivations, reachedLimits: limits,
            searchStrategiesAgree: strategiesAgree, repetitionsStable: repetitionsStable,
            generalizedEvidenceFingerprint: fingerprints[0],
            evidenceFingerprint: ResearchFingerprint.make(Data(evidence.utf8)),
            timing: timing(timings), failures: failures
        )
    }

    private static func fingerprint(_ result: GrammarGeneralizedParseResult) -> String {
        let value = [
            result.status.rawValue,
            result.forest.alternatives.map(\.id).sorted().joined(separator: ","),
            String(result.sharedForest.derivationCount(upTo: Int.max)),
            result.reachedLimits.map(\.rawValue).sorted().joined(separator: ",")
        ].joined(separator: "\u{1f}")
        return ResearchFingerprint.make(Data(value.utf8))
    }

    private static func timing(_ values: [UInt64]) -> GrammarResearchTimingSummary {
        let ordered = values.sorted()
        guard !ordered.isEmpty else {
            return .init(samples: 0, minimumNanoseconds: 0, medianNanoseconds: 0,
                         percentile95Nanoseconds: 0, maximumNanoseconds: 0)
        }
        let median = ordered[(ordered.count - 1) / 2]
        let p95 = ordered[min(ordered.count - 1, Int(ceil(Double(ordered.count) * 0.95)) - 1)]
        return .init(samples: ordered.count, minimumNanoseconds: ordered[0],
                     medianNanoseconds: median, percentile95Nanoseconds: p95,
                     maximumNanoseconds: ordered[ordered.count - 1])
    }

    private static var platformName: String {
#if os(macOS)
        "macOS"
#elseif os(Linux)
        "Linux"
#elseif os(Windows)
        "Windows"
#else
        "unknown"
#endif
    }
}

private enum ResearchFingerprint {
    static func make(_ data: Data) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return String(format: "%016llx", hash)
    }
}
