import Foundation

public struct GrammarPublicResearchIndex: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1
    public static let kindIdentifier = "grammar-workbench-public-research-index"

    public struct Claim: Identifiable, Hashable, Codable, Sendable {
        public let id: String
        public let statement: String
        public let evidence: [String]

        public init(id: String, statement: String, evidence: [String]) {
            self.id = id
            self.statement = statement
            self.evidence = evidence
        }
    }

    public let schemaVersion: Int
    public let kind: String
    public let title: String
    public let claims: [Claim]
    public let nonClaims: [String]
    public let reproductionEntryPoints: [String]

    public init(title: String) {
        schemaVersion = Self.currentSchemaVersion
        kind = Self.kindIdentifier
        self.title = title
        claims = [
            .init(
                id: "bounded-parser-conformance",
                statement: "The declared parser studies pass their bounded, executable hypotheses for the pinned ecosystem.",
                evidence: ["validation-programme.json", "validation-report.json", "corpus.json", "ecosystem.json"]
            ),
            .init(
                id: "reproducible-semantic-evidence",
                statement: "Repeated selected studies preserve one semantic evidence identity independently of timing.",
                evidence: ["validation-report.json", "benchmark-report.json"]
            ),
            .init(
                id: "environment-qualified-macrobenchmark",
                statement: "The selected-study macrobenchmark retains raw samples, host metadata, and correctness evidence.",
                evidence: ["benchmark-protocol.json", "benchmark-report.json"]
            ),
        ]
        nonClaims = [
            "The release is not a formal proof of parser correctness.",
            "The bounded corpus is not an exhaustive description of context-free languages.",
            "Timing measurements are not comparable across different environment identities.",
            "The macrobenchmark does not rank individual parser engines.",
            "The recorded sample count does not establish statistical significance.",
        ]
        reproductionEntryPoints = [
            "grammar-workbench research-validate validation-programme.json reproduced-validation-report.json",
            "grammar-workbench research-benchmark benchmark-protocol.json reproduced-benchmark-report.json",
            "grammar-workbench public-research-release-verify .",
        ]
    }
}

public struct GrammarPublicResearchReleaseFile: Hashable, Codable, Sendable {
    public let path: String
    public let mediaType: String
    public let bytes: Int
    public let sha256: String
}

public struct GrammarPublicResearchReleaseManifest: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1
    public static let kindIdentifier = "grammar-workbench-public-research-release"
    public static let manifestFilename = "manifest.json"
    public static let requiredFiles = [
        "CITATION.cff", "LICENSE.txt", "README.md", "benchmark-protocol.json",
        "benchmark-report.json", "capabilities.json", "corpus.json", "ecosystem.json",
        "research-index.json", "validation-programme.json", "validation-report.json",
    ]

    public let schemaVersion: Int
    public let kind: String
    public let title: String
    public let softwareVersion: String
    public let publicAPIVersion: Int
    public let repository: String
    public let sourceRevision: String
    public let ecosystemContractVersion: String
    public let capabilityLedgerVersion: String
    public let corpusVersion: Int
    public let validationEvidenceFingerprint: String
    public let benchmarkProtocolFingerprint: String
    public let benchmarkEvidenceFingerprint: String
    public let benchmarkMeasurementFingerprint: String
    public let digestAlgorithm: String
    public let license: String
    public let files: [GrammarPublicResearchReleaseFile]
}

public struct GrammarPublicResearchReleaseBundle: Sendable {
    public let manifest: GrammarPublicResearchReleaseManifest
    public let files: [String: Data]

    public func manifestData() throws -> Data {
        try GrammarPublicResearchRelease.encoder.encode(manifest)
    }
}

public enum GrammarPublicResearchReleaseError: Error, LocalizedError, Sendable {
    case invalidInput(String)
    case invalidManifest(String)
    case missingFile(String)
    case unexpectedFile(String)
    case digestMismatch(String)

    public var errorDescription: String? {
        switch self {
        case .invalidInput(let value): "Invalid public research input: \(value)"
        case .invalidManifest(let value): "Invalid public research release: \(value)"
        case .missingFile(let path): "Public research release is missing ‘\(path)’."
        case .unexpectedFile(let path): "Public research release contains undeclared file ‘\(path)’."
        case .digestMismatch(let path): "Public research release digest differs for ‘\(path)’."
        }
    }
}

/// The archival boundary for the public research release. It composes existing
/// evidence contracts and validates their links without taking ownership from
/// Grammar, Parser, Compiler, Grammar-REPL, or the parser engines.
public enum GrammarPublicResearchRelease {
    public static let maximumInputBytes = 16 * 1_024 * 1_024
    static let encoder: JSONEncoder = {
        let value = JSONEncoder()
        value.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return value
    }()

    public static func create(
        programmeData: Data,
        benchmarkProtocolData: Data,
        ecosystemData: Data,
        capabilityLedgerData: Data,
        corpusData: Data,
        licenseData: Data,
        sourceRevision: String
    ) throws -> GrammarPublicResearchReleaseBundle {
        try validateInputSizes([
            programmeData, benchmarkProtocolData, ecosystemData,
            capabilityLedgerData, corpusData, licenseData,
        ])
        guard sourceRevision.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil else {
            throw GrammarPublicResearchReleaseError.invalidInput("Source revision must be a full Git revision.")
        }
        guard !licenseData.isEmpty else {
            throw GrammarPublicResearchReleaseError.invalidInput("License text is empty.")
        }

        let programme = try GrammarResearchProgrammeCodec.decode(programmeData)
        let validationReport = try GrammarResearchValidator.run(programme)
        guard validationReport.passed else {
            throw GrammarPublicResearchReleaseError.invalidInput("Validation hypotheses did not pass.")
        }
        let benchmarkProtocol = try GrammarResearchBenchmarkCodec.decodeProtocol(benchmarkProtocolData)
        let benchmarkReport = try GrammarResearchBenchmarkRunner.run(benchmarkProtocol)
        guard benchmarkReport.passed else {
            throw GrammarPublicResearchReleaseError.invalidInput("Benchmark correctness evidence did not pass.")
        }
        let ecosystem = try ecosystemIdentity(ecosystemData)
        let capabilities = try capabilityIdentity(capabilityLedgerData)
        let corpus = try corpusIdentity(corpusData)
        let title = "Grammar Workbench public research release"
        let index = GrammarPublicResearchIndex(title: title)

        let files: [String: Data] = [
            "CITATION.cff": Data(citation(title: title).utf8),
            "LICENSE.txt": licenseData,
            "README.md": Data(readme(
                sourceRevision: sourceRevision,
                validationEvidence: validationReport.evidenceFingerprint,
                benchmarkMeasurement: benchmarkReport.measurementFingerprint,
                ecosystemVersion: ecosystem.version,
                corpusVersion: corpus.version
            ).utf8),
            "benchmark-protocol.json": try GrammarResearchBenchmarkCodec.encode(benchmarkProtocol),
            "benchmark-report.json": try GrammarResearchBenchmarkCodec.encode(benchmarkReport),
            "capabilities.json": capabilities.data,
            "corpus.json": corpus.data,
            "ecosystem.json": ecosystem.data,
            "research-index.json": try encoder.encode(index),
            "validation-programme.json": try GrammarResearchProgrammeCodec.encode(programme),
            "validation-report.json": try GrammarResearchProgrammeCodec.encode(validationReport),
        ]
        let entries = files.keys.sorted().map { path in
            let data = files[path]!
            return GrammarPublicResearchReleaseFile(
                path: path, mediaType: mediaType(path), bytes: data.count,
                sha256: ResearchSHA256.hexDigest(data)
            )
        }
        let manifest = GrammarPublicResearchReleaseManifest(
            schemaVersion: GrammarPublicResearchReleaseManifest.currentSchemaVersion,
            kind: GrammarPublicResearchReleaseManifest.kindIdentifier,
            title: title,
            softwareVersion: GrammarWorkbenchRelease.version,
            publicAPIVersion: GrammarWorkbenchAPIVersion.current,
            repository: "https://github.com/hakkabon/Grammar-Workbench",
            sourceRevision: sourceRevision,
            ecosystemContractVersion: ecosystem.version,
            capabilityLedgerVersion: capabilities.version,
            corpusVersion: corpus.version,
            validationEvidenceFingerprint: validationReport.evidenceFingerprint,
            benchmarkProtocolFingerprint: benchmarkReport.protocolFingerprint,
            benchmarkEvidenceFingerprint: benchmarkReport.studyReport.evidenceFingerprint,
            benchmarkMeasurementFingerprint: benchmarkReport.measurementFingerprint,
            digestAlgorithm: "sha256", license: "MIT", files: entries
        )
        return .init(manifest: manifest, files: files)
    }

    public static func decodeManifest(_ data: Data) throws -> GrammarPublicResearchReleaseManifest {
        guard data.count <= maximumInputBytes else {
            throw GrammarPublicResearchReleaseError.invalidManifest("Manifest exceeds 16 MiB.")
        }
        let value = try JSONDecoder().decode(GrammarPublicResearchReleaseManifest.self, from: data)
        guard value.schemaVersion == GrammarPublicResearchReleaseManifest.currentSchemaVersion,
              value.kind == GrammarPublicResearchReleaseManifest.kindIdentifier,
              value.softwareVersion.range(
                of: "^[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression
              ) != nil,
              value.publicAPIVersion == GrammarWorkbenchAPIVersion.current,
              value.repository == "https://github.com/hakkabon/Grammar-Workbench",
              value.sourceRevision.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil,
              !value.ecosystemContractVersion.isEmpty,
              !value.capabilityLedgerVersion.isEmpty,
              value.corpusVersion >= 5,
              [value.validationEvidenceFingerprint, value.benchmarkProtocolFingerprint,
               value.benchmarkEvidenceFingerprint, value.benchmarkMeasurementFingerprint]
                .allSatisfy({ $0.range(of: "^[0-9a-f]{16}$", options: .regularExpression) != nil }),
              value.digestAlgorithm == "sha256", value.license == "MIT" else {
            throw GrammarPublicResearchReleaseError.invalidManifest("Header fields are unsupported or incomplete.")
        }
        let paths = value.files.map(\.path)
        guard paths == paths.sorted(), Set(paths).count == paths.count,
              paths == GrammarPublicResearchReleaseManifest.requiredFiles,
              value.files.allSatisfy({
                  $0.bytes > 0 && $0.bytes <= maximumInputBytes
                      && $0.mediaType == mediaType($0.path)
                      && $0.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
              }) else {
            throw GrammarPublicResearchReleaseError.invalidManifest("File inventory is incomplete or invalid.")
        }
        return value
    }

    public static func verify(
        manifestData: Data,
        files: [String: Data]
    ) throws -> GrammarPublicResearchReleaseManifest {
        let manifest = try decodeManifest(manifestData)
        let declared = Set(manifest.files.map(\.path))
        if let path = files.keys.first(where: { !declared.contains($0) }) {
            throw GrammarPublicResearchReleaseError.unexpectedFile(path)
        }
        for entry in manifest.files {
            guard let data = files[entry.path] else {
                throw GrammarPublicResearchReleaseError.missingFile(entry.path)
            }
            guard data.count == entry.bytes, data.count <= maximumInputBytes,
                  ResearchSHA256.hexDigest(data) == entry.sha256 else {
                throw GrammarPublicResearchReleaseError.digestMismatch(entry.path)
            }
        }

        let programme = try GrammarResearchProgrammeCodec.decode(files["validation-programme.json"]!)
        let validation = try GrammarResearchProgrammeCodec.decodeReport(files["validation-report.json"]!)
        let protocolValue = try GrammarResearchBenchmarkCodec.decodeProtocol(files["benchmark-protocol.json"]!)
        let benchmark = try GrammarResearchBenchmarkCodec.decodeReport(files["benchmark-report.json"]!)
        let ecosystem = try ecosystemIdentity(files["ecosystem.json"]!)
        let capabilities = try capabilityIdentity(files["capabilities.json"]!)
        let corpus = try corpusIdentity(files["corpus.json"]!)
        let index = try JSONDecoder().decode(GrammarPublicResearchIndex.self, from: files["research-index.json"]!)
        try validate(index)

        guard validation.programmeID == programme.id,
              validation.programmeFingerprint == (try GrammarResearchProgrammeCodec.fingerprint(programme)),
              validation.evidenceFingerprint == manifest.validationEvidenceFingerprint,
              validation.passed,
              benchmark.protocolID == protocolValue.id,
              benchmark.protocolFingerprint == (try GrammarResearchBenchmarkCodec.fingerprint(protocolValue)),
              benchmark.protocolFingerprint == manifest.benchmarkProtocolFingerprint,
              benchmark.studyReport.evidenceFingerprint == manifest.benchmarkEvidenceFingerprint,
              benchmark.measurementFingerprint == manifest.benchmarkMeasurementFingerprint,
              benchmark.environment.grammarWorkbenchVersion == manifest.softwareVersion,
              benchmark.passed,
              ecosystem.version == manifest.ecosystemContractVersion,
              capabilities.version == manifest.capabilityLedgerVersion,
              corpus.version == manifest.corpusVersion else {
            throw GrammarPublicResearchReleaseError.invalidManifest(
                "Programme, benchmark, ecosystem, capability, corpus, or release identities disagree."
            )
        }
        return manifest
    }

    private struct JSONIdentity {
        let data: Data
        let version: String
    }

    private struct CorpusIdentity {
        let data: Data
        let version: Int
    }

    private static func ecosystemIdentity(_ data: Data) throws -> JSONIdentity {
        let object = try object(data)
        guard object["schemaVersion"] as? Int == 1,
              let version = object["contractVersion"] as? String,
              version.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil,
              let repositories = object["repositories"] as? [[String: Any]],
              repositories.count == 12,
              Set(repositories.compactMap { $0["name"] as? String }).count == repositories.count,
              repositories.allSatisfy({
                  ($0["version"] as? String)?.range(
                    of: "^[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression
                  ) != nil
                  && ($0["revision"] as? String)?.range(
                    of: "^[0-9a-f]{40}$", options: .regularExpression
                  ) != nil
              }) else {
            throw GrammarPublicResearchReleaseError.invalidInput("Ecosystem pins are incomplete.")
        }
        return .init(data: try canonical(object), version: version)
    }

    private static func capabilityIdentity(_ data: Data) throws -> JSONIdentity {
        let object = try object(data)
        guard object["schemaVersion"] as? Int == 1,
              let version = object["ledgerVersion"] as? String, !version.isEmpty,
              let capabilities = object["capabilities"] as? [[String: Any]],
              let repositories = object["repositories"] as? [[String: Any]],
              let engines = object["engines"] as? [[String: Any]],
              capabilities.count >= 16, repositories.count == 12, engines.count == 10,
              Set(capabilities.compactMap { $0["id"] as? String }).count == capabilities.count else {
            throw GrammarPublicResearchReleaseError.invalidInput("Capability ledger is incomplete.")
        }
        return .init(data: try canonical(object), version: version)
    }

    private static func corpusIdentity(_ data: Data) throws -> CorpusIdentity {
        let object = try object(data)
        guard let version = object["schemaVersion"] as? Int, version >= 5,
              let engines = object["engines"] as? [[String: Any]], engines.count == 10,
              let grammars = object["grammars"] as? [[String: Any]], grammars.count >= 5,
              let cases = object["cases"] as? [[String: Any]], cases.count >= 49,
              Set(engines.compactMap { $0["id"] as? String }).count == engines.count else {
            throw GrammarPublicResearchReleaseError.invalidInput("Shared corpus is incomplete.")
        }
        return .init(data: try canonical(object), version: version)
    }

    private static func validate(_ index: GrammarPublicResearchIndex) throws {
        let evidence = Set(GrammarPublicResearchReleaseManifest.requiredFiles)
        guard index.schemaVersion == GrammarPublicResearchIndex.currentSchemaVersion,
              index.kind == GrammarPublicResearchIndex.kindIdentifier,
              !index.title.isEmpty, index.claims.count == 3, index.nonClaims.count == 5,
              index.reproductionEntryPoints.count == 3,
              Set(index.claims.map(\.id)).count == index.claims.count,
              index.claims.allSatisfy({
                  !$0.id.isEmpty && !$0.statement.isEmpty && !$0.evidence.isEmpty
                      && $0.evidence.allSatisfy(evidence.contains)
              }) else {
            throw GrammarPublicResearchReleaseError.invalidManifest("Research claim index is invalid.")
        }
    }

    private static func validateInputSizes(_ values: [Data]) throws {
        guard values.allSatisfy({ $0.count <= maximumInputBytes }) else {
            throw GrammarPublicResearchReleaseError.invalidInput("An input exceeds 16 MiB.")
        }
    }

    private static func object(_ data: Data) throws -> [String: Any] {
        guard data.count <= maximumInputBytes,
              let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GrammarPublicResearchReleaseError.invalidInput("Expected a bounded JSON object.")
        }
        return value
    }

    private static func canonical(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    private static func citation(title: String) -> String {
        """
        cff-version: 1.2.0
        message: "If you use this software or its research evidence, please cite it."
        title: "\(title)"
        type: software
        authors:
          - family-names: "Akerstedt-Inoue"
            given-names: "Ulf"
        version: "\(GrammarWorkbenchRelease.version)"
        date-released: "2026-10-20"
        repository-code: "https://github.com/hakkabon/Grammar-Workbench"
        license: MIT
        """ + "\n"
    }

    private static func readme(
        sourceRevision: String,
        validationEvidence: String,
        benchmarkMeasurement: String,
        ecosystemVersion: String,
        corpusVersion: Int
    ) -> String {
        """
        # Grammar Workbench public research release

        This archive is the independently verifiable research companion to Grammar
        Workbench \(GrammarWorkbenchRelease.version), source revision `\(sourceRevision)`.

        ## Verify and reproduce

        1. Run `grammar-workbench public-research-release-verify .`.
        2. Re-run `grammar-workbench research-validate validation-programme.json reproduced-validation-report.json`.
        3. Compare semantic evidence fingerprint `\(validationEvidence)`.
        4. Re-run `grammar-workbench research-benchmark benchmark-protocol.json reproduced-benchmark-report.json` on an otherwise idle host.
        5. Compare benchmark timings only when protocol and environment identities match.

        Ecosystem contract \(ecosystemVersion) pins the participating repositories;
        shared corpus v\(corpusVersion) records the cross-engine cases. `research-index.json`
        states the supported claims and, equally importantly, the non-claims. Exact
        host-sensitive measurements have fingerprint `\(benchmarkMeasurement)`.

        All payloads are inventoried with SHA-256 in `manifest.json`. Semantic
        fingerprints identify evidence, not bytes or performance.
        """ + "\n"
    }

    private static func mediaType(_ path: String) -> String {
        if path.hasSuffix(".json") { return "application/json" }
        if path.hasSuffix(".md") { return "text/markdown" }
        if path.hasSuffix(".cff") { return "text/yaml" }
        return "text/plain"
    }
}
