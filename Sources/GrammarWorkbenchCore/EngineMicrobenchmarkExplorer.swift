import Foundation
import Parser

/// Workbench projection of engine-owned Parser microbenchmark reports.
/// Workbench never executes engine workloads or rewrites their correctness evidence.
public struct GrammarEngineMicrobenchmarkExplorerReport: Hashable, Codable, Sendable {
    public let reports: [Report]
    public let environmentCount: Int
    public let ownerCount: Int
    public let engineCount: Int
    public let ratioPolicy: String

    public struct Report: Identifiable, Hashable, Codable, Sendable {
        public var id: String { "\(owner)/\(engineID)/\(suiteID)/\(measurementFingerprint)" }
        public let owner: String
        public let ownerVersion: String
        public let engineID: String
        public let suiteID: String
        public let suiteTitle: String
        public let buildConfiguration: String
        public let environment: ParserEngineMicrobenchmarkEnvironment
        public let suiteFingerprint: String
        public let measurementFingerprint: String
        public let cases: [Case]
    }

    public struct Case: Identifiable, Hashable, Codable, Sendable {
        public var id: String { caseID }
        public let caseID: String
        public let title: String
        public let operation: String
        public let boundary: String
        public let scale: Int
        public let sampleCount: Int
        public let medianNanoseconds: UInt64
        public let percentile95Nanoseconds: UInt64
        public let evidenceFingerprint: String
        public let counters: [String: Int]
    }
}

public enum GrammarEngineMicrobenchmarkExplorer {
    public static func decode(_ data: Data) throws -> ParserEngineMicrobenchmarkReport {
        try ParserEngineMicrobenchmarkCodec.decodeReport(data)
    }

    public static func inspect(
        _ reports: [ParserEngineMicrobenchmarkReport]
    ) throws -> GrammarEngineMicrobenchmarkExplorerReport {
        guard !reports.isEmpty, reports.count <= 64 else {
            throw GrammarEngineMicrobenchmarkExplorerError.invalidReportCount
        }
        for report in reports {
            _ = try ParserEngineMicrobenchmarkCodec.decodeReport(
                ParserEngineMicrobenchmarkCodec.encode(report)
            )
        }
        let identities = reports.map {
            "\($0.suite.owner.repository)/\($0.suite.engineID)/\($0.suite.id)/\($0.measurementFingerprint)"
        }
        guard Set(identities).count == identities.count else {
            throw GrammarEngineMicrobenchmarkExplorerError.duplicateReport
        }
        let projected = reports.map { report in
            GrammarEngineMicrobenchmarkExplorerReport.Report(
                owner: report.suite.owner.repository,
                ownerVersion: report.suite.owner.version,
                engineID: report.suite.engineID,
                suiteID: report.suite.id,
                suiteTitle: report.suite.title,
                buildConfiguration: report.suite.buildConfiguration.rawValue,
                environment: report.environment,
                suiteFingerprint: report.suiteFingerprint,
                measurementFingerprint: report.measurementFingerprint,
                cases: zip(report.suite.cases, report.results).map { item, result in
                    .init(
                        caseID: item.id, title: item.title,
                        operation: item.operation.rawValue, boundary: item.boundary,
                        scale: item.scale,
                        sampleCount: result.durationsNanoseconds.count,
                        medianNanoseconds: result.timing.medianNanoseconds,
                        percentile95Nanoseconds: result.timing.percentile95Nanoseconds,
                        evidenceFingerprint: result.evidenceFingerprint,
                        counters: result.counters
                    )
                }
            )
        }.sorted {
            ($0.owner, $0.engineID, $0.suiteID, $0.measurementFingerprint)
                < ($1.owner, $1.engineID, $1.suiteID, $1.measurementFingerprint)
        }
        return .init(
            reports: projected,
            environmentCount: Set(reports.map(\.environment)).count,
            ownerCount: Set(reports.map(\.suite.owner.repository)).count,
            engineCount: Set(reports.map(\.suite.engineID)).count,
            ratioPolicy: "Ratios are emitted only for the same suite fingerprint, environment, and correctness evidence; cross-engine rows remain descriptive."
        )
    }

    public static func compare(
        baseline: ParserEngineMicrobenchmarkReport,
        candidate: ParserEngineMicrobenchmarkReport
    ) -> ParserEngineMicrobenchmarkComparison {
        ParserEngineMicrobenchmarkRunner.compare(baseline: baseline, candidate: candidate)
    }
}

public enum GrammarEngineMicrobenchmarkExplorerError: Error, LocalizedError, Sendable {
    case invalidReportCount
    case duplicateReport

    public var errorDescription: String? {
        switch self {
        case .invalidReportCount:
            "The engine benchmark explorer requires between 1 and 64 reports."
        case .duplicateReport:
            "The engine benchmark explorer received the same measurement more than once."
        }
    }
}
