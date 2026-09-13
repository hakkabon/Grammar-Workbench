import Foundation

public struct GrammarResearchDistributionFile: Hashable, Codable, Sendable {
    public let path: String
    public let mediaType: String
    public let bytes: Int
    public let sha256: String

    public init(path: String, mediaType: String, bytes: Int, sha256: String) {
        self.path = path
        self.mediaType = mediaType
        self.bytes = bytes
        self.sha256 = sha256
    }
}

public struct GrammarResearchDistributionManifest: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1
    public static let kindIdentifier = "grammar-workbench-research-distribution"
    public static let manifestFilename = "manifest.json"
    public static let requiredFiles = [
        "CITATION.cff", "LICENSE.txt", "README.md", "ecosystem.json",
        "programme.json", "report.json",
    ]

    public let schemaVersion: Int
    public let kind: String
    public let title: String
    public let softwareVersion: String
    public let publicAPIVersion: Int
    public let programmeID: String
    public let programmeFingerprint: String
    public let evidenceFingerprint: String
    public let ecosystemContractVersion: String
    public let digestAlgorithm: String
    public let license: String
    public let files: [GrammarResearchDistributionFile]
}

public struct GrammarResearchDistributionBundle: Sendable {
    public let manifest: GrammarResearchDistributionManifest
    public let files: [String: Data]

    public func manifestData() throws -> Data {
        try GrammarResearchDistribution.encoder().encode(manifest)
    }
}

public enum GrammarResearchDistributionError: Error, LocalizedError, Sendable {
    case invalidEcosystem(String)
    case invalidManifest(String)
    case missingFile(String)
    case unexpectedFile(String)
    case digestMismatch(String)
    case hypothesesFailed

    public var errorDescription: String? {
        switch self {
        case .invalidEcosystem(let message): "Invalid ecosystem evidence: \(message)"
        case .invalidManifest(let message): "Invalid research distribution: \(message)"
        case .missingFile(let path): "Research distribution is missing ‘\(path)’."
        case .unexpectedFile(let path): "Research distribution contains undeclared file ‘\(path)’."
        case .digestMismatch(let path): "Research distribution digest differs for ‘\(path)’."
        case .hypothesesFailed: "Research distribution was not created because one or more hypotheses failed."
        }
    }
}

/// Builds and verifies the directory payload used for archival research releases.
/// Evidence identity remains independent of timing; SHA-256 protects the exact files.
public enum GrammarResearchDistribution {
    static func encoder() -> JSONEncoder {
        let value = JSONEncoder()
        value.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return value
    }

    public static func create(
        programmeData: Data,
        ecosystemData: Data,
        licenseData: Data
    ) throws -> GrammarResearchDistributionBundle {
        let programme = try GrammarResearchProgrammeCodec.decode(programmeData)
        let report = try GrammarResearchValidator.run(programme)
        guard report.passed else { throw GrammarResearchDistributionError.hypothesesFailed }
        let ecosystem = try ecosystemIdentity(ecosystemData)
        guard !licenseData.isEmpty else {
            throw GrammarResearchDistributionError.invalidManifest("License text is empty.")
        }

        let canonicalProgramme = try GrammarResearchProgrammeCodec.encode(programme)
        let reportData = try GrammarResearchProgrammeCodec.encode(report)
        let canonicalEcosystem = try JSONSerialization.data(
            withJSONObject: ecosystem.object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        let citation = Data(citation(title: programme.title).utf8)
        let readme = Data(protocolReadme(programme: programme, report: report, ecosystem: ecosystem).utf8)
        let contents: [String: Data] = [
            "CITATION.cff": citation,
            "LICENSE.txt": licenseData,
            "README.md": readme,
            "ecosystem.json": canonicalEcosystem,
            "programme.json": canonicalProgramme,
            "report.json": reportData,
        ]
        let entries = contents.keys.sorted().map { path in
            let data = contents[path]!
            return GrammarResearchDistributionFile(
                path: path, mediaType: mediaType(path), bytes: data.count,
                sha256: ResearchSHA256.hexDigest(data)
            )
        }
        let manifest = GrammarResearchDistributionManifest(
            schemaVersion: GrammarResearchDistributionManifest.currentSchemaVersion,
            kind: GrammarResearchDistributionManifest.kindIdentifier,
            title: programme.title,
            softwareVersion: GrammarWorkbenchRelease.version,
            publicAPIVersion: GrammarWorkbenchAPIVersion.current,
            programmeID: programme.id,
            programmeFingerprint: try GrammarResearchProgrammeCodec.fingerprint(programme),
            evidenceFingerprint: report.evidenceFingerprint,
            ecosystemContractVersion: ecosystem.contractVersion,
            digestAlgorithm: "sha256", license: "MIT", files: entries
        )
        return .init(manifest: manifest, files: contents)
    }

    public static func decodeManifest(_ data: Data) throws -> GrammarResearchDistributionManifest {
        let value = try JSONDecoder().decode(GrammarResearchDistributionManifest.self, from: data)
        guard value.schemaVersion == GrammarResearchDistributionManifest.currentSchemaVersion,
              value.kind == GrammarResearchDistributionManifest.kindIdentifier,
              value.digestAlgorithm == "sha256", value.license == "MIT",
              value.publicAPIVersion == GrammarWorkbenchAPIVersion.current,
              !value.title.isEmpty, !value.programmeID.isEmpty,
              value.softwareVersion.range(
                of: "^[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression
              ) != nil,
              value.programmeFingerprint.count == 16,
              value.evidenceFingerprint.count == 16,
              !value.ecosystemContractVersion.isEmpty else {
            throw GrammarResearchDistributionError.invalidManifest("Header fields are unsupported or incomplete.")
        }
        let paths = value.files.map(\.path)
        guard paths == paths.sorted(), Set(paths).count == paths.count,
              paths == GrammarResearchDistributionManifest.requiredFiles else {
            throw GrammarResearchDistributionError.invalidManifest("File inventory is incomplete or unordered.")
        }
        guard value.files.allSatisfy({
            $0.bytes > 0
                && $0.mediaType == mediaType($0.path)
                && $0.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
        }) else {
            throw GrammarResearchDistributionError.invalidManifest("File size or SHA-256 metadata is invalid.")
        }
        return value
    }

    public static func verify(
        manifestData: Data,
        files: [String: Data]
    ) throws -> GrammarResearchDistributionManifest {
        let manifest = try decodeManifest(manifestData)
        let declared = Set(manifest.files.map(\.path))
        if let unexpected = files.keys.first(where: { !declared.contains($0) }) {
            throw GrammarResearchDistributionError.unexpectedFile(unexpected)
        }
        for entry in manifest.files {
            guard let data = files[entry.path] else {
                throw GrammarResearchDistributionError.missingFile(entry.path)
            }
            guard data.count == entry.bytes, ResearchSHA256.hexDigest(data) == entry.sha256 else {
                throw GrammarResearchDistributionError.digestMismatch(entry.path)
            }
        }
        let programme = try GrammarResearchProgrammeCodec.decode(files["programme.json"]!)
        let report = try GrammarResearchProgrammeCodec.decodeReport(files["report.json"]!)
        let ecosystem = try ecosystemIdentity(files["ecosystem.json"]!)
        guard programme.id == manifest.programmeID,
              try GrammarResearchProgrammeCodec.fingerprint(programme) == manifest.programmeFingerprint,
              report.programmeID == programme.id,
              report.programmeFingerprint == manifest.programmeFingerprint,
              report.evidenceFingerprint == manifest.evidenceFingerprint,
              report.environment.grammarWorkbenchVersion == manifest.softwareVersion,
              report.environment.apiVersion == manifest.publicAPIVersion,
              ecosystem.contractVersion == manifest.ecosystemContractVersion,
              report.passed else {
            throw GrammarResearchDistributionError.invalidManifest("Programme, report, environment, or ecosystem identities disagree.")
        }
        return manifest
    }

    private struct EcosystemIdentity {
        let object: [String: Any]
        let contractVersion: String
        let repositories: Int
    }

    private static func ecosystemIdentity(_ data: Data) throws -> EcosystemIdentity {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["schemaVersion"] as? Int == 1,
              let contractVersion = object["contractVersion"] as? String,
              contractVersion.range(
                of: "^[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression
              ) != nil,
              let repositories = object["repositories"] as? [[String: Any]],
              !repositories.isEmpty,
              repositories.allSatisfy({ repository in
                  guard let name = repository["name"] as? String,
                        let version = repository["version"] as? String,
                        let revision = repository["revision"] as? String else { return false }
                  return !name.isEmpty
                      && version.range(
                        of: "^[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression
                      ) != nil
                      && revision.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil
              }),
              Set(repositories.compactMap { $0["name"] as? String }).count == repositories.count else {
            throw GrammarResearchDistributionError.invalidEcosystem(
                "Expected a schema-1 contract with versioned, revision-pinned repositories."
            )
        }
        return .init(object: object, contractVersion: contractVersion, repositories: repositories.count)
    }

    private static func citation(title: String) -> String {
        """
        cff-version: 1.2.0
        message: "If you use this software or evidence bundle, please cite it."
        title: "\(yamlQuoted(title))"
        type: software
        authors:
          - family-names: "Akerstedt-Inoue"
            given-names: "Ulf"
        version: "\(GrammarWorkbenchRelease.version)"
        date-released: "2026-09-13"
        repository-code: "https://github.com/hakkabon/Grammar-Workbench"
        license: MIT
        """ + "\n"
    }

    private static func protocolReadme(
        programme: GrammarResearchProgramme,
        report: GrammarResearchReport,
        ecosystem: EcosystemIdentity
    ) -> String {
        """
        # \(programme.title)

        This is a self-verifying Grammar Workbench research distribution.

        ## Reproduce

        1. Build Grammar Workbench \(GrammarWorkbenchRelease.version) with Swift 6.
        2. Run `grammar-workbench research-validate programme.json reproduced-report.json`.
        3. Compare `evidenceFingerprint` with `\(report.evidenceFingerprint)`.
        4. Run `grammar-workbench research-package-verify .` to verify this inventory.

        The programme contains \(programme.cases.count) explicit hypotheses and requests
        \(programme.repetitions) repetitions. Ecosystem contract \(ecosystem.contractVersion)
        pins \(ecosystem.repositories) repositories. Timing measurements describe the host
        and are deliberately excluded from semantic evidence identity.

        ## Contents

        - `programme.json`: executable hypotheses and bounds.
        - `report.json`: observed evidence and timings.
        - `ecosystem.json`: exact cross-repository versions and revisions.
        - `manifest.json`: SHA-256 inventory and linked identities.
        - `CITATION.cff`: citation metadata.
        - `LICENSE.txt`: distribution terms.
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

private enum ResearchSHA256 {
    private static let constants: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    static func hexDigest(_ data: Data) -> String {
        var bytes = Array(data)
        let bitLength = UInt64(bytes.count) * 8
        bytes.append(0x80)
        while bytes.count % 64 != 56 { bytes.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8((bitLength >> UInt64(shift)) & 0xff))
        }
        var hash: [UInt32] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
        ]
        for offset in stride(from: 0, to: bytes.count, by: 64) {
            var words = Array(repeating: UInt32(0), count: 64)
            for index in 0..<16 {
                let start = offset + index * 4
                words[index] = UInt32(bytes[start]) << 24 | UInt32(bytes[start + 1]) << 16
                    | UInt32(bytes[start + 2]) << 8 | UInt32(bytes[start + 3])
            }
            for index in 16..<64 {
                let x = words[index - 15]
                let y = words[index - 2]
                let s0 = rotate(x, 7) ^ rotate(x, 18) ^ (x >> 3)
                let s1 = rotate(y, 17) ^ rotate(y, 19) ^ (y >> 10)
                words[index] = words[index - 16] &+ s0 &+ words[index - 7] &+ s1
            }
            var state = hash
            for index in 0..<64 {
                let s1 = rotate(state[4], 6) ^ rotate(state[4], 11) ^ rotate(state[4], 25)
                let choose = (state[4] & state[5]) ^ (~state[4] & state[6])
                let temporary1 = state[7] &+ s1 &+ choose &+ constants[index] &+ words[index]
                let s0 = rotate(state[0], 2) ^ rotate(state[0], 13) ^ rotate(state[0], 22)
                let majority = (state[0] & state[1]) ^ (state[0] & state[2]) ^ (state[1] & state[2])
                let temporary2 = s0 &+ majority
                state = [temporary1 &+ temporary2, state[0], state[1], state[2], state[3] &+ temporary1, state[4], state[5], state[6]]
            }
            for index in hash.indices { hash[index] = hash[index] &+ state[index] }
        }
        return hash.map { String(format: "%08x", $0) }.joined()
    }

    private static func rotate(_ value: UInt32, _ amount: UInt32) -> UInt32 {
        (value >> amount) | (value << (32 - amount))
    }
}
