import Foundation

/// A versioned declaration of exactly what a published Workbench benchmark runs.
/// This is a macrobenchmark of complete selected studies, not an engine microbenchmark.
public struct GrammarResearchBenchmarkProtocol: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1
    public static let kindIdentifier = "grammar-workbench-benchmark-protocol"

    public let schemaVersion: Int
    public let kind: String
    public let id: String
    public let title: String
    public let rationale: String
    public let buildConfiguration: String
    public let warmupIterations: Int
    public let measurementIterations: Int
    public let studyIDs: [String]

    public init(
        id: String,
        title: String,
        rationale: String,
        buildConfiguration: String = "release",
        warmupIterations: Int = 1,
        measurementIterations: Int = 5,
        studyIDs: [String] = GrammarSelectedResearchCatalog.studies.map(\.id)
    ) {
        schemaVersion = Self.currentSchemaVersion
        kind = Self.kindIdentifier
        self.id = id
        self.title = title
        self.rationale = rationale
        self.buildConfiguration = buildConfiguration
        self.warmupIterations = warmupIterations
        self.measurementIterations = measurementIterations
        self.studyIDs = studyIDs
    }

    public static let publication = Self(
        id: "org.grammar-workbench.selected-studies.v1",
        title: "Grammar Workbench selected-study macrobenchmark",
        rationale: "Measure complete, correctness-checked research studies under a declared host and build configuration."
    )
}

public struct GrammarResearchBenchmarkEnvironment: Hashable, Codable, Sendable {
    public let grammarWorkbenchVersion: String
    public let apiVersion: Int
    public let platform: String
    public let architecture: String
    public let operatingSystemVersion: String
    public let processorCount: Int
    public let activeProcessorCount: Int
    public let physicalMemoryBytes: UInt64
    public let buildConfiguration: String

    public var comparisonIdentity: String {
        [platform, architecture, operatingSystemVersion, String(processorCount),
         String(activeProcessorCount), String(physicalMemoryBytes), buildConfiguration]
            .joined(separator: "\u{1f}")
    }
}

public struct GrammarResearchBenchmarkResult: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let title: String
    public let evidenceFingerprint: String
    public let durationsNanoseconds: [UInt64]
    public let timing: GrammarResearchTimingSummary
}

public struct GrammarResearchBenchmarkReport: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1
    public static let kindIdentifier = "grammar-workbench-benchmark-report"

    public let schemaVersion: Int
    public let kind: String
    public let protocolID: String
    public let protocolFingerprint: String
    public let environment: GrammarResearchBenchmarkEnvironment
    public let studyReport: GrammarResearchStudyExplorerReport
    public let results: [GrammarResearchBenchmarkResult]
    /// Integrity identity for the exact measurements and host. It is not semantic evidence.
    public let measurementFingerprint: String

    public var passed: Bool { studyReport.passed && studyReport.reproducible }
}

public struct GrammarResearchBenchmarkComparison: Hashable, Codable, Sendable {
    public struct Result: Identifiable, Hashable, Codable, Sendable {
        public let id: String
        public let baselineMedianNanoseconds: UInt64
        public let candidateMedianNanoseconds: UInt64
        public let medianRatio: Double?
    }

    public let compatibleProtocol: Bool
    public let compatibleEnvironment: Bool
    public let compatibleEvidence: Bool
    public let comparable: Bool
    public let results: [Result]
    public let qualification: String
}

public enum GrammarResearchBenchmarkError: Error, LocalizedError, Sendable {
    case unsupportedVersion(Int)
    case invalidKind(String)
    case invalidProtocol(String)
    case invalidReport(String)
    case evidenceChanged(String)
    case invalidPublication(String)
    case missingFile(String)
    case unexpectedFile(String)
    case digestMismatch(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let value): "Unsupported benchmark schema version \(value)."
        case .invalidKind(let value): "Unexpected benchmark artifact kind ‘\(value)’ ."
        case .invalidProtocol(let value): "Invalid benchmark protocol: \(value)"
        case .invalidReport(let value): "Invalid benchmark report: \(value)"
        case .evidenceChanged(let study): "Study evidence changed while benchmarking ‘\(study)’ ."
        case .invalidPublication(let value): "Invalid benchmark publication: \(value)"
        case .missingFile(let path): "Benchmark publication is missing ‘\(path)’ ."
        case .unexpectedFile(let path): "Benchmark publication contains undeclared file ‘\(path)’ ."
        case .digestMismatch(let path): "Benchmark publication digest differs for ‘\(path)’ ."
        }
    }
}

public enum GrammarResearchBenchmarkCodec {
    public static func encode(_ value: GrammarResearchBenchmarkProtocol) throws -> Data {
        try validate(value)
        return try prettyEncoder().encode(value)
    }

    public static func decodeProtocol(_ data: Data) throws -> GrammarResearchBenchmarkProtocol {
        let value = try JSONDecoder().decode(GrammarResearchBenchmarkProtocol.self, from: data)
        try validate(value)
        return value
    }

    public static func encode(_ value: GrammarResearchBenchmarkReport) throws -> Data {
        try validate(value)
        return try prettyEncoder().encode(value)
    }

    public static func decodeReport(_ data: Data) throws -> GrammarResearchBenchmarkReport {
        let value = try JSONDecoder().decode(GrammarResearchBenchmarkReport.self, from: data)
        try validate(value)
        return value
    }

    public static func fingerprint(_ value: GrammarResearchBenchmarkProtocol) throws -> String {
        try validate(value)
        return ResearchFingerprint.make(try canonicalEncoder().encode(value))
    }

    static func measurementFingerprint(
        protocolFingerprint: String,
        environment: GrammarResearchBenchmarkEnvironment,
        studyEvidenceFingerprint: String,
        results: [GrammarResearchBenchmarkResult]
    ) -> String {
        let measurements = results.sorted { $0.id < $1.id }.map {
            "\($0.id):\($0.evidenceFingerprint):\($0.durationsNanoseconds.map(String.init).joined(separator: ","))"
        }.joined(separator: "\n")
        return ResearchFingerprint.make(Data(
            "\(protocolFingerprint)\n\(environment.comparisonIdentity)\n\(studyEvidenceFingerprint)\n\(measurements)".utf8
        ))
    }

    private static func validate(_ value: GrammarResearchBenchmarkProtocol) throws {
        guard value.schemaVersion == GrammarResearchBenchmarkProtocol.currentSchemaVersion else {
            throw GrammarResearchBenchmarkError.unsupportedVersion(value.schemaVersion)
        }
        guard value.kind == GrammarResearchBenchmarkProtocol.kindIdentifier else {
            throw GrammarResearchBenchmarkError.invalidKind(value.kind)
        }
        guard !value.id.isEmpty, !value.title.isEmpty, !value.rationale.isEmpty else {
            throw GrammarResearchBenchmarkError.invalidProtocol("Identity and explanatory fields are required.")
        }
        guard ["debug", "release"].contains(value.buildConfiguration) else {
            throw GrammarResearchBenchmarkError.invalidProtocol("Build configuration must be debug or release.")
        }
        guard (0...10).contains(value.warmupIterations),
              (3...50).contains(value.measurementIterations) else {
            throw GrammarResearchBenchmarkError.invalidProtocol("Warmups must be 0...10 and measurements 3...50.")
        }
        guard !value.studyIDs.isEmpty, Set(value.studyIDs).count == value.studyIDs.count,
              value.studyIDs.allSatisfy({ GrammarSelectedResearchCatalog.study(id: $0) != nil }) else {
            throw GrammarResearchBenchmarkError.invalidProtocol("Study identifiers must be unique members of the selected catalog.")
        }
    }

    private static func validate(_ value: GrammarResearchBenchmarkReport) throws {
        guard value.schemaVersion == GrammarResearchBenchmarkReport.currentSchemaVersion else {
            throw GrammarResearchBenchmarkError.unsupportedVersion(value.schemaVersion)
        }
        guard value.kind == GrammarResearchBenchmarkReport.kindIdentifier else {
            throw GrammarResearchBenchmarkError.invalidKind(value.kind)
        }
        _ = try GrammarResearchStudyExplorerCodec.decode(
            GrammarResearchStudyExplorerCodec.encode(value.studyReport)
        )
        guard !value.protocolID.isEmpty, value.protocolFingerprint.count == 16,
              value.measurementFingerprint.count == 16,
              value.environment.apiVersion == GrammarWorkbenchAPIVersion.current,
              !value.environment.platform.isEmpty, !value.environment.architecture.isEmpty,
              !value.results.isEmpty, Set(value.results.map(\.id)).count == value.results.count else {
            throw GrammarResearchBenchmarkError.invalidReport("Header, environment, or result inventory is incomplete.")
        }
        for result in value.results {
            guard result.durationsNanoseconds.count >= 3,
                  result.timing == timing(result.durationsNanoseconds),
                  value.studyReport.studies.contains(where: {
                      $0.studyID == result.id && $0.title == result.title
                          && $0.report.evidenceFingerprint == result.evidenceFingerprint
                  }) else {
                throw GrammarResearchBenchmarkError.invalidReport("Result ‘\(result.id)’ is inconsistent with its samples or evidence.")
            }
        }
        guard measurementFingerprint(
            protocolFingerprint: value.protocolFingerprint,
            environment: value.environment,
            studyEvidenceFingerprint: value.studyReport.evidenceFingerprint,
            results: value.results
        ) == value.measurementFingerprint else {
            throw GrammarResearchBenchmarkError.invalidReport("Measurement fingerprint does not match the report.")
        }
    }

    static func timing(_ values: [UInt64]) -> GrammarResearchTimingSummary {
        let ordered = values.sorted()
        guard !ordered.isEmpty else {
            return .init(samples: 0, minimumNanoseconds: 0, medianNanoseconds: 0,
                         percentile95Nanoseconds: 0, maximumNanoseconds: 0)
        }
        return .init(
            samples: ordered.count,
            minimumNanoseconds: ordered[0],
            medianNanoseconds: ordered[(ordered.count - 1) / 2],
            percentile95Nanoseconds: ordered[min(
                ordered.count - 1, Int(ceil(Double(ordered.count) * 0.95)) - 1
            )],
            maximumNanoseconds: ordered[ordered.count - 1]
        )
    }

    private static func prettyEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func canonicalEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

public enum GrammarResearchBenchmarkRunner {
    public static func run(
        _ protocolValue: GrammarResearchBenchmarkProtocol
    ) throws -> GrammarResearchBenchmarkReport {
        let protocolFingerprint = try GrammarResearchBenchmarkCodec.fingerprint(protocolValue)
        let baseline = try GrammarResearchStudyExplorerEngine.runCatalog()
        let baselineByID = Dictionary(uniqueKeysWithValues: baseline.studies.map { ($0.studyID, $0) })
        var results: [GrammarResearchBenchmarkResult] = []
        for id in protocolValue.studyIDs {
            let study = GrammarSelectedResearchCatalog.study(id: id)!
            let expected = baselineByID[id]!
            for _ in 0..<protocolValue.warmupIterations {
                let preview = try GrammarSelectedResearchPreviewEngine.run(study)
                guard preview.report.evidenceFingerprint == expected.report.evidenceFingerprint else {
                    throw GrammarResearchBenchmarkError.evidenceChanged(id)
                }
            }
            var durations: [UInt64] = []
            for _ in 0..<protocolValue.measurementIterations {
                let start = portableTimestampNanoseconds()
                let preview = try GrammarSelectedResearchPreviewEngine.run(study)
                durations.append(portableElapsedNanoseconds(since: start))
                guard preview.report.evidenceFingerprint == expected.report.evidenceFingerprint else {
                    throw GrammarResearchBenchmarkError.evidenceChanged(id)
                }
            }
            results.append(.init(
                id: id, title: study.title,
                evidenceFingerprint: expected.report.evidenceFingerprint,
                durationsNanoseconds: durations,
                timing: GrammarResearchBenchmarkCodec.timing(durations)
            ))
        }
        let environment = currentEnvironment(buildConfiguration: protocolValue.buildConfiguration)
        let fingerprint = GrammarResearchBenchmarkCodec.measurementFingerprint(
            protocolFingerprint: protocolFingerprint, environment: environment,
            studyEvidenceFingerprint: baseline.evidenceFingerprint, results: results
        )
        let report = GrammarResearchBenchmarkReport(
            schemaVersion: GrammarResearchBenchmarkReport.currentSchemaVersion,
            kind: GrammarResearchBenchmarkReport.kindIdentifier,
            protocolID: protocolValue.id, protocolFingerprint: protocolFingerprint,
            environment: environment, studyReport: baseline, results: results,
            measurementFingerprint: fingerprint
        )
        return try GrammarResearchBenchmarkCodec.decodeReport(
            GrammarResearchBenchmarkCodec.encode(report)
        )
    }

    public static func compare(
        baseline: GrammarResearchBenchmarkReport,
        candidate: GrammarResearchBenchmarkReport
    ) -> GrammarResearchBenchmarkComparison {
        let sameProtocol = baseline.protocolID == candidate.protocolID
            && baseline.protocolFingerprint == candidate.protocolFingerprint
        let sameEnvironment = baseline.environment.comparisonIdentity
            == candidate.environment.comparisonIdentity
        let sameEvidence = baseline.studyReport.evidenceFingerprint
            == candidate.studyReport.evidenceFingerprint
        let comparable = sameProtocol && sameEnvironment && sameEvidence
        let old = Dictionary(uniqueKeysWithValues: baseline.results.map { ($0.id, $0) })
        let new = Dictionary(uniqueKeysWithValues: candidate.results.map { ($0.id, $0) })
        let ids = Set(old.keys).intersection(new.keys).sorted()
        return .init(
            compatibleProtocol: sameProtocol, compatibleEnvironment: sameEnvironment,
            compatibleEvidence: sameEvidence,
            comparable: comparable,
            results: ids.map { id in
                let before = old[id]!.timing.medianNanoseconds
                let after = new[id]!.timing.medianNanoseconds
                return .init(
                    id: id, baselineMedianNanoseconds: before,
                    candidateMedianNanoseconds: after,
                    medianRatio: comparable && before > 0 ? Double(after) / Double(before) : nil
                )
            },
            qualification: comparable
                ? "Descriptive medians are comparable under the same protocol and recorded environment; no statistical significance is implied."
                : "Timing ratios are withheld because protocol, environment, or semantic evidence identities differ."
        )
    }

    private static func currentEnvironment(
        buildConfiguration: String
    ) -> GrammarResearchBenchmarkEnvironment {
#if os(WASI)
        return .init(
            grammarWorkbenchVersion: GrammarWorkbenchRelease.version,
            apiVersion: GrammarWorkbenchAPIVersion.current,
            platform: "WASI", architecture: "wasm32",
            operatingSystemVersion: "WASI",
            processorCount: 1, activeProcessorCount: 1, physicalMemoryBytes: 0,
            buildConfiguration: buildConfiguration
        )
#else
        let info = ProcessInfo.processInfo
#if os(macOS)
        let platform = "macOS"
#elseif os(Linux)
        let platform = "Linux"
#elseif os(Windows)
        let platform = "Windows"
#else
        let platform = "unknown"
#endif
#if arch(arm64)
        let architecture = "arm64"
#elseif arch(x86_64)
        let architecture = "x86_64"
#elseif arch(wasm32)
        let architecture = "wasm32"
#else
        let architecture = "unknown"
#endif
        return .init(
            grammarWorkbenchVersion: GrammarWorkbenchRelease.version,
            apiVersion: GrammarWorkbenchAPIVersion.current,
            platform: platform, architecture: architecture,
            operatingSystemVersion: info.operatingSystemVersionString,
            processorCount: info.processorCount,
            activeProcessorCount: info.activeProcessorCount,
            physicalMemoryBytes: info.physicalMemory,
            buildConfiguration: buildConfiguration
        )
#endif
    }
}

public struct GrammarResearchBenchmarkPublicationFile: Hashable, Codable, Sendable {
    public let path: String
    public let mediaType: String
    public let bytes: Int
    public let sha256: String
}

public struct GrammarResearchBenchmarkPublicationManifest: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1
    public static let kindIdentifier = "grammar-workbench-benchmark-publication"
    public static let manifestFilename = "manifest.json"
    public static let requiredFiles = [
        "CITATION.cff", "LICENSE.txt", "README.md", "benchmark-protocol.json",
        "benchmark-report.json", "ecosystem.json",
    ]

    public let schemaVersion: Int
    public let kind: String
    public let title: String
    public let softwareVersion: String
    public let publicAPIVersion: Int
    public let protocolID: String
    public let protocolFingerprint: String
    public let studyEvidenceFingerprint: String
    public let measurementFingerprint: String
    public let ecosystemContractVersion: String
    public let digestAlgorithm: String
    public let license: String
    public let files: [GrammarResearchBenchmarkPublicationFile]
}

public struct GrammarResearchBenchmarkPublicationBundle: Sendable {
    public let manifest: GrammarResearchBenchmarkPublicationManifest
    public let files: [String: Data]

    public func manifestData() throws -> Data {
        try GrammarResearchBenchmarkPublication.encoder().encode(manifest)
    }
}

/// A self-verifying, citation-ready bundle. SHA-256 protects the exact timing
/// samples while the nested study fingerprint independently identifies truth evidence.
public enum GrammarResearchBenchmarkPublication {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static func create(
        protocolData: Data,
        ecosystemData: Data,
        licenseData: Data
    ) throws -> GrammarResearchBenchmarkPublicationBundle {
        let protocolValue = try GrammarResearchBenchmarkCodec.decodeProtocol(protocolData)
        let report = try GrammarResearchBenchmarkRunner.run(protocolValue)
        let ecosystem = try ecosystemIdentity(ecosystemData)
        guard !licenseData.isEmpty else {
            throw GrammarResearchBenchmarkError.invalidPublication("License text is empty.")
        }
        let canonicalProtocol = try GrammarResearchBenchmarkCodec.encode(protocolValue)
        let reportData = try GrammarResearchBenchmarkCodec.encode(report)
        let canonicalEcosystem = try JSONSerialization.data(
            withJSONObject: ecosystem.object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        let files: [String: Data] = [
            "CITATION.cff": Data(citation(title: protocolValue.title).utf8),
            "LICENSE.txt": licenseData,
            "README.md": Data(readme(
                protocolValue: protocolValue, report: report,
                ecosystemVersion: ecosystem.contractVersion
            ).utf8),
            "benchmark-protocol.json": canonicalProtocol,
            "benchmark-report.json": reportData,
            "ecosystem.json": canonicalEcosystem,
        ]
        let entries = files.keys.sorted().map { path in
            let data = files[path]!
            return GrammarResearchBenchmarkPublicationFile(
                path: path, mediaType: mediaType(path), bytes: data.count,
                sha256: ResearchSHA256.hexDigest(data)
            )
        }
        return .init(
            manifest: .init(
                schemaVersion: GrammarResearchBenchmarkPublicationManifest.currentSchemaVersion,
                kind: GrammarResearchBenchmarkPublicationManifest.kindIdentifier,
                title: protocolValue.title,
                softwareVersion: GrammarWorkbenchRelease.version,
                publicAPIVersion: GrammarWorkbenchAPIVersion.current,
                protocolID: protocolValue.id,
                protocolFingerprint: report.protocolFingerprint,
                studyEvidenceFingerprint: report.studyReport.evidenceFingerprint,
                measurementFingerprint: report.measurementFingerprint,
                ecosystemContractVersion: ecosystem.contractVersion,
                digestAlgorithm: "sha256", license: "MIT", files: entries
            ),
            files: files
        )
    }

    public static func decodeManifest(
        _ data: Data
    ) throws -> GrammarResearchBenchmarkPublicationManifest {
        let value = try JSONDecoder().decode(
            GrammarResearchBenchmarkPublicationManifest.self, from: data
        )
        guard value.schemaVersion == GrammarResearchBenchmarkPublicationManifest.currentSchemaVersion,
              value.kind == GrammarResearchBenchmarkPublicationManifest.kindIdentifier,
              value.digestAlgorithm == "sha256", value.license == "MIT",
              value.publicAPIVersion == GrammarWorkbenchAPIVersion.current,
              !value.title.isEmpty, !value.protocolID.isEmpty,
              value.softwareVersion.range(
                of: "^[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression
              ) != nil,
              value.protocolFingerprint.count == 16,
              value.studyEvidenceFingerprint.count == 16,
              value.measurementFingerprint.count == 16,
              !value.ecosystemContractVersion.isEmpty else {
            throw GrammarResearchBenchmarkError.invalidPublication("Header fields are unsupported or incomplete.")
        }
        let paths = value.files.map(\.path)
        guard paths == paths.sorted(), Set(paths).count == paths.count,
              paths == GrammarResearchBenchmarkPublicationManifest.requiredFiles,
              value.files.allSatisfy({
                  $0.bytes > 0 && $0.mediaType == mediaType($0.path)
                      && $0.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
              }) else {
            throw GrammarResearchBenchmarkError.invalidPublication("File inventory is incomplete or invalid.")
        }
        return value
    }

    public static func verify(
        manifestData: Data,
        files: [String: Data]
    ) throws -> GrammarResearchBenchmarkPublicationManifest {
        let manifest = try decodeManifest(manifestData)
        let declared = Set(manifest.files.map(\.path))
        if let path = files.keys.first(where: { !declared.contains($0) }) {
            throw GrammarResearchBenchmarkError.unexpectedFile(path)
        }
        for entry in manifest.files {
            guard let data = files[entry.path] else {
                throw GrammarResearchBenchmarkError.missingFile(entry.path)
            }
            guard data.count == entry.bytes, ResearchSHA256.hexDigest(data) == entry.sha256 else {
                throw GrammarResearchBenchmarkError.digestMismatch(entry.path)
            }
        }
        let protocolValue = try GrammarResearchBenchmarkCodec.decodeProtocol(
            files["benchmark-protocol.json"]!
        )
        let report = try GrammarResearchBenchmarkCodec.decodeReport(
            files["benchmark-report.json"]!
        )
        let ecosystem = try ecosystemIdentity(files["ecosystem.json"]!)
        guard protocolValue.id == manifest.protocolID,
              try GrammarResearchBenchmarkCodec.fingerprint(protocolValue) == manifest.protocolFingerprint,
              report.protocolID == manifest.protocolID,
              report.protocolFingerprint == manifest.protocolFingerprint,
              report.results.map(\.id) == protocolValue.studyIDs,
              report.environment.buildConfiguration == protocolValue.buildConfiguration,
              report.studyReport.evidenceFingerprint == manifest.studyEvidenceFingerprint,
              report.measurementFingerprint == manifest.measurementFingerprint,
              report.environment.grammarWorkbenchVersion == manifest.softwareVersion,
              ecosystem.contractVersion == manifest.ecosystemContractVersion,
              report.passed else {
            throw GrammarResearchBenchmarkError.invalidPublication(
                "Protocol, report, environment, or ecosystem identities disagree."
            )
        }
        return manifest
    }

    private struct EcosystemIdentity {
        let object: [String: Any]
        let contractVersion: String
    }

    private static func ecosystemIdentity(_ data: Data) throws -> EcosystemIdentity {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["schemaVersion"] as? Int == 1,
              let version = object["contractVersion"] as? String,
              version.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil,
              let repositories = object["repositories"] as? [[String: Any]],
              !repositories.isEmpty,
              repositories.allSatisfy({ repository in
                  guard let name = repository["name"] as? String,
                        let packageVersion = repository["version"] as? String,
                        let revision = repository["revision"] as? String else { return false }
                  return !name.isEmpty
                      && packageVersion.range(
                        of: "^[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression
                      ) != nil
                      && revision.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil
              }),
              Set(repositories.compactMap { $0["name"] as? String }).count == repositories.count else {
            throw GrammarResearchBenchmarkError.invalidPublication(
                "Expected a schema-1 contract with versioned, revision-pinned repositories."
            )
        }
        return .init(object: object, contractVersion: version)
    }

    private static func citation(title: String) -> String {
        """
        cff-version: 1.2.0
        message: "If you use this benchmark publication, please cite it."
        title: "\(yamlQuoted(title))"
        type: software
        authors:
          - family-names: "Akerstedt-Inoue"
            given-names: "Ulf"
        version: "\(GrammarWorkbenchRelease.version)"
        date-released: "2026-10-17"
        repository-code: "https://github.com/hakkabon/Grammar-Workbench"
        license: MIT
        """ + "\n"
    }

    private static func readme(
        protocolValue: GrammarResearchBenchmarkProtocol,
        report: GrammarResearchBenchmarkReport,
        ecosystemVersion: String
    ) -> String {
        """
        # \(protocolValue.title)

        This is a self-verifying Grammar Workbench benchmark publication.

        ## Reproduce

        1. Build Grammar Workbench \(GrammarWorkbenchRelease.version) in `\(protocolValue.buildConfiguration)` configuration.
        2. Run `grammar-workbench research-benchmark benchmark-protocol.json reproduced-report.json` on an otherwise idle host.
        3. Compare semantic `studyReport.evidenceFingerprint` first.
        4. Compare timings only when protocol and environment identities match.
        5. Run `grammar-workbench research-benchmark-package-verify .` to verify this inventory.

        The protocol uses \(protocolValue.warmupIterations) warmup and
        \(protocolValue.measurementIterations) measured iterations for
        \(protocolValue.studyIDs.count) selected studies. Ecosystem contract
        \(ecosystemVersion) pins the repository revisions.

        Timing samples are environment-sensitive descriptive measurements, not
        semantic evidence or a claim of statistical significance. The nested
        study report is the correctness gate. Its evidence fingerprint is
        `\(report.studyReport.evidenceFingerprint)`; the exact host and timing
        payload has measurement fingerprint `\(report.measurementFingerprint)`.
        """ + "\n"
    }

    private static func yamlQuoted(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func mediaType(_ path: String) -> String {
        if path.hasSuffix(".json") { return "application/json" }
        if path.hasSuffix(".md") { return "text/markdown" }
        if path.hasSuffix(".cff") { return "text/yaml" }
        return "text/plain"
    }
}
