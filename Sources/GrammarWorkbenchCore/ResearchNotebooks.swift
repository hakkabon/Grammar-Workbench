import Foundation

/// Read-only Workbench projection of Grammar-REPL's experiment-project schema.
/// Grammar-REPL remains the owner of project capture and fingerprint verification.
public struct GrammarREPLExperimentProjectArtifact: Hashable, Sendable {
    public static let supportedSchemaVersion = 1
    public static let supportedFingerprintAlgorithm = "fnv1a64"

    public let schemaVersion: Int
    public let producer: GrammarREPLExperimentArtifact.Producer
    public let name: String
    public let description: String?
    public let experiments: [Entry]
    public let fingerprintAlgorithm: String
    public let fingerprint: String

    public struct Entry: Identifiable, Hashable, Sendable {
        public let id: String
        public let title: String?
        public let tags: [String]
        public let experiment: GrammarREPLExperimentArtifact
    }

    public var totalEngines: Int { experiments.reduce(0) { $0 + $1.experiment.engines.count } }
    public var divergentExperiments: Int {
        experiments.count { $0.experiment.agreement == .divergent }
    }

    public func experiment(id: String) -> Entry? {
        experiments.first { $0.id == id }
    }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 128 * 1_024 * 1_024 else {
            throw GrammarResearchNotebookError.artifactTooLarge
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let schemaVersion = root["schemaVersion"] as? Int,
              let producerObject = root["producer"] as? [String: Any],
              let producerName = producerObject["name"] as? String,
              let producerVersion = producerObject["version"] as? String,
              let name = root["name"] as? String,
              let entryObjects = root["experiments"] as? [[String: Any]],
              let fingerprintAlgorithm = root["fingerprintAlgorithm"] as? String,
              let fingerprint = root["fingerprint"] as? String else {
            throw GrammarResearchNotebookError.malformedProject
        }
        let entries = try entryObjects.map { object -> Entry in
            guard let id = object["id"] as? String,
                  let tags = object["tags"] as? [String],
                  let experimentObject = object["experiment"] as? [String: Any] else {
                throw GrammarResearchNotebookError.malformedProject
            }
            let experimentData = try JSONSerialization.data(
                withJSONObject: experimentObject, options: [.sortedKeys]
            )
            return Entry(
                id: id,
                title: object["title"] as? String,
                tags: tags,
                experiment: try GrammarREPLExperimentArtifact.decode(experimentData)
            )
        }
        let value = Self(
            schemaVersion: schemaVersion,
            producer: .init(name: producerName, version: producerVersion),
            name: name,
            description: root["description"] as? String,
            experiments: entries,
            fingerprintAlgorithm: fingerprintAlgorithm,
            fingerprint: fingerprint
        )
        try value.validate()
        return value
    }

    public func validate() throws {
        guard schemaVersion == Self.supportedSchemaVersion else {
            throw GrammarResearchNotebookError.unsupportedProjectSchema(schemaVersion)
        }
        guard producer.name == "Grammar-REPL",
              Self.compatibleProducerVersion(producer.version) else {
            throw GrammarResearchNotebookError.invalidProjectProducer
        }
        guard !name.isEmpty,
              name == name.trimmingCharacters(in: .whitespacesAndNewlines),
              description?.isEmpty != true,
              experiments.count <= 1_024,
              fingerprintAlgorithm == Self.supportedFingerprintAlgorithm,
              fingerprint.range(of: "^[0-9a-f]{16}$", options: .regularExpression) != nil else {
            throw GrammarResearchNotebookError.invalidProjectMetadata
        }
        let identifiers = experiments.map(\.id)
        guard identifiers == identifiers.sorted(), Set(identifiers).count == identifiers.count else {
            throw GrammarResearchNotebookError.invalidProjectEntries
        }
        for entry in experiments {
            guard !entry.id.isEmpty,
                  entry.id == entry.id.trimmingCharacters(in: .whitespacesAndNewlines),
                  entry.title?.isEmpty != true,
                  entry.tags == Array(Set(entry.tags)).sorted(),
                  entry.tags.allSatisfy({ !$0.isEmpty }) else {
                throw GrammarResearchNotebookError.invalidProjectEntries
            }
            try entry.experiment.validate()
        }
    }

    private static func compatibleProducerVersion(_ value: String) -> Bool {
        let components = value.split(separator: ".").compactMap { Int($0) }
        guard components.count == 3 else { return false }
        return components.lexicographicallyPrecedes([0, 9, 0]) == false
    }
}

public enum GrammarREPLExperimentImport: Sendable {
    case experiment(GrammarREPLExperimentArtifact)
    case project(GrammarREPLExperimentProjectArtifact)

    public static func decode(_ data: Data) throws -> Self {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GrammarResearchNotebookError.malformedProject
        }
        if root["experiments"] != nil {
            return .project(try GrammarREPLExperimentProjectArtifact.decode(data))
        }
        return .experiment(try GrammarREPLExperimentArtifact.decode(data))
    }
}

/// Workbench-owned narrative over immutable Grammar-REPL project evidence.
/// It stores stable identities and summaries, never source paths or timestamps.
public struct GrammarResearchNotebook: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1
    public static let kindIdentifier = "grammar-workbench-research-notebook"
    public static let fingerprintAlgorithm = "fnv1a64"

    public let schemaVersion: Int
    public let kind: String
    public let producer: Producer
    public let title: String
    public let researchQuestion: String
    public let project: ProjectReference
    public let cells: [Cell]
    public let fingerprintAlgorithm: String
    public let fingerprint: String

    public struct Producer: Hashable, Codable, Sendable {
        public let name: String
        public let version: String
    }

    public struct ProjectReference: Hashable, Codable, Sendable {
        public let name: String
        public let fingerprint: String
        public let producerVersion: String
        public let experiments: [ExperimentReference]

        public struct ExperimentReference: Identifiable, Hashable, Codable, Sendable {
            public let id: String
            public let title: String?
            public let tags: [String]
            public let fingerprint: String
            public let input: String
            public let agreement: GrammarREPLExperimentArtifact.Agreement
            public let engines: [String]
        }

        init(_ project: GrammarREPLExperimentProjectArtifact) {
            name = project.name
            fingerprint = project.fingerprint
            producerVersion = project.producer.version
            experiments = project.experiments.map {
                ExperimentReference(
                    id: $0.id, title: $0.title, tags: $0.tags,
                    fingerprint: $0.experiment.fingerprint,
                    input: $0.experiment.input,
                    agreement: $0.experiment.agreement,
                    engines: $0.experiment.engines
                )
            }
        }

        public func experiment(id: String) -> ExperimentReference? {
            experiments.first { $0.id == id }
        }
    }

    public enum CellKind: String, Hashable, Codable, Sendable {
        case note
        case evidence
        case conclusion
    }

    public struct Cell: Identifiable, Hashable, Codable, Sendable {
        public let id: String
        public let kind: CellKind
        public let title: String
        public let body: String
        public let experimentID: String?
        public let selectedEngines: [String]

        public init(
            id: String,
            kind: CellKind,
            title: String,
            body: String,
            experimentID: String? = nil,
            selectedEngines: [String] = []
        ) {
            self.id = id
            self.kind = kind
            self.title = title
            self.body = body
            self.experimentID = experimentID
            self.selectedEngines = selectedEngines
        }
    }

    public static func create(
        title: String,
        researchQuestion: String,
        project: GrammarREPLExperimentProjectArtifact,
        cells: [Cell] = []
    ) throws -> Self {
        try assemble(
            producer: .init(name: "Grammar-Workbench", version: GrammarWorkbenchRelease.version),
            title: title,
            researchQuestion: researchQuestion,
            project: .init(project),
            cells: cells
        )
    }

    public func adding(_ cell: Cell) throws -> Self {
        try Self.assemble(
            producer: producer,
            title: title,
            researchQuestion: researchQuestion,
            project: project,
            cells: cells + [cell]
        )
    }

    public func json(prettyPrinted: Bool = true) throws -> Data {
        try GrammarResearchNotebookCodec.encode(self, prettyPrinted: prettyPrinted)
    }

    public static func decode(_ data: Data) throws -> Self {
        try GrammarResearchNotebookCodec.decode(data)
    }

    public func resolve(
        against projectArtifact: GrammarREPLExperimentProjectArtifact
    ) -> GrammarResearchNotebookResolution {
        let actual = ProjectReference(projectArtifact)
        let projectMatches = project == actual
        let unresolved = cells.filter { cell in
            guard cell.kind == .evidence, let id = cell.experimentID,
                  let entry = projectArtifact.experiment(id: id) else {
                return cell.kind == .evidence
            }
            return !Set(cell.selectedEngines).isSubset(of: Set(entry.experiment.engines))
        }.map(\.id)
        return .init(
            projectMatches: projectMatches,
            evidenceCellCount: cells.count { $0.kind == .evidence },
            unresolvedCellIDs: unresolved
        )
    }

    private static func assemble(
        producer: Producer,
        title: String,
        researchQuestion: String,
        project: ProjectReference,
        cells: [Cell]
    ) throws -> Self {
        let payload = FingerprintPayload(
            schemaVersion: currentSchemaVersion,
            kind: kindIdentifier,
            producer: producer,
            title: title,
            researchQuestion: researchQuestion,
            project: project,
            cells: cells,
            fingerprintAlgorithm: fingerprintAlgorithm
        )
        let fingerprint = ResearchFingerprint.make(try canonicalEncoder().encode(payload))
        let value = Self(
            schemaVersion: currentSchemaVersion,
            kind: kindIdentifier,
            producer: producer,
            title: title,
            researchQuestion: researchQuestion,
            project: project,
            cells: cells,
            fingerprintAlgorithm: fingerprintAlgorithm,
            fingerprint: fingerprint
        )
        try GrammarResearchNotebookCodec.validate(value)
        return value
    }

    fileprivate struct FingerprintPayload: Codable {
        let schemaVersion: Int
        let kind: String
        let producer: Producer
        let title: String
        let researchQuestion: String
        let project: ProjectReference
        let cells: [Cell]
        let fingerprintAlgorithm: String
    }
}

public struct GrammarResearchNotebookResolution: Hashable, Codable, Sendable {
    public let projectMatches: Bool
    public let evidenceCellCount: Int
    public let unresolvedCellIDs: [String]

    public var isResolved: Bool { projectMatches && unresolvedCellIDs.isEmpty }
}

public struct GrammarREPLExperimentProjectExplorerReport: Hashable, Codable, Sendable {
    public let schemaVersion: Int
    public let name: String
    public let producerVersion: String
    public let fingerprint: String
    public let fingerprintStatus: String
    public let experimentCount: Int
    public let divergentExperimentCount: Int
    public let experiments: [Experiment]

    public struct Experiment: Identifiable, Hashable, Codable, Sendable {
        public let id: String
        public let title: String?
        public let tags: [String]
        public let fingerprint: String
        public let input: String
        public let agreement: GrammarREPLExperimentArtifact.Agreement
        public let summary: GrammarREPLExperimentSummary
    }

    public init(_ project: GrammarREPLExperimentProjectArtifact) {
        schemaVersion = project.schemaVersion
        name = project.name
        producerVersion = project.producer.version
        fingerprint = project.fingerprint
        fingerprintStatus = "recorded-requires-grammar-repl-verification"
        experimentCount = project.experiments.count
        divergentExperimentCount = project.divergentExperiments
        experiments = project.experiments.map {
            Experiment(
                id: $0.id, title: $0.title, tags: $0.tags,
                fingerprint: $0.experiment.fingerprint,
                input: $0.experiment.input,
                agreement: $0.experiment.agreement,
                summary: $0.experiment.summary
            )
        }
    }
}

public struct GrammarResearchNotebookExplorerReport: Hashable, Codable, Sendable {
    public let schemaVersion: Int
    public let title: String
    public let researchQuestion: String
    public let notebookFingerprint: String
    public let projectName: String
    public let projectFingerprint: String
    public let cellCount: Int
    public let evidenceCellCount: Int
    public let conclusionCount: Int
    public let resolution: GrammarResearchNotebookResolution?

    public init(
        _ notebook: GrammarResearchNotebook,
        project: GrammarREPLExperimentProjectArtifact? = nil
    ) {
        schemaVersion = notebook.schemaVersion
        title = notebook.title
        researchQuestion = notebook.researchQuestion
        notebookFingerprint = notebook.fingerprint
        projectName = notebook.project.name
        projectFingerprint = notebook.project.fingerprint
        cellCount = notebook.cells.count
        evidenceCellCount = notebook.cells.count { $0.kind == .evidence }
        conclusionCount = notebook.cells.count { $0.kind == .conclusion }
        resolution = project.map(notebook.resolve)
    }
}

public enum GrammarResearchNotebookCodec {
    public static func encode(
        _ notebook: GrammarResearchNotebook,
        prettyPrinted: Bool = true
    ) throws -> Data {
        try validate(notebook)
        let encoder = canonicalEncoder()
        if prettyPrinted {
            encoder.outputFormatting.insert(.prettyPrinted)
        }
        return try encoder.encode(notebook)
    }

    public static func decode(_ data: Data) throws -> GrammarResearchNotebook {
        guard data.count <= 16 * 1_024 * 1_024 else {
            throw GrammarResearchNotebookError.artifactTooLarge
        }
        let value: GrammarResearchNotebook
        do { value = try JSONDecoder().decode(GrammarResearchNotebook.self, from: data) }
        catch { throw GrammarResearchNotebookError.malformedNotebook(String(describing: error)) }
        try validate(value)
        return value
    }

    static func validate(_ value: GrammarResearchNotebook) throws {
        guard value.schemaVersion == GrammarResearchNotebook.currentSchemaVersion else {
            throw GrammarResearchNotebookError.unsupportedNotebookSchema(value.schemaVersion)
        }
        guard value.kind == GrammarResearchNotebook.kindIdentifier,
              value.producer.name == "Grammar-Workbench",
              !value.producer.version.isEmpty,
              value.fingerprintAlgorithm == GrammarResearchNotebook.fingerprintAlgorithm,
              value.fingerprint.range(of: "^[0-9a-f]{16}$", options: .regularExpression) != nil,
              canonical(value.title), canonical(value.researchQuestion),
              canonical(value.project.name),
              value.project.fingerprint.range(of: "^[0-9a-f]{16}$", options: .regularExpression) != nil,
              !value.project.producerVersion.isEmpty,
              value.project.experiments.count <= 1_024,
              value.cells.count <= 4_096 else {
            throw GrammarResearchNotebookError.invalidNotebookMetadata
        }
        let experimentIDs = value.project.experiments.map(\.id)
        guard experimentIDs == experimentIDs.sorted(),
              Set(experimentIDs).count == experimentIDs.count else {
            throw GrammarResearchNotebookError.invalidNotebookEvidence
        }
        var experimentByID: [String: GrammarResearchNotebook.ProjectReference.ExperimentReference] = [:]
        for experiment in value.project.experiments {
            guard canonical(experiment.id),
                  experiment.fingerprint.range(of: "^[0-9a-f]{16}$", options: .regularExpression) != nil,
                  experiment.tags == Array(Set(experiment.tags)).sorted(),
                  experiment.engines == GrammarREPLExperimentArtifact.canonicalEngines.filter(Set(experiment.engines).contains) else {
                throw GrammarResearchNotebookError.invalidNotebookEvidence
            }
            experimentByID[experiment.id] = experiment
        }
        guard Set(value.cells.map(\.id)).count == value.cells.count else {
            throw GrammarResearchNotebookError.duplicateCellID
        }
        for cell in value.cells {
            guard canonical(cell.id), canonical(cell.title), canonical(cell.body) else {
                throw GrammarResearchNotebookError.invalidNotebookCell(cell.id)
            }
            switch cell.kind {
            case .note, .conclusion:
                guard cell.experimentID == nil, cell.selectedEngines.isEmpty else {
                    throw GrammarResearchNotebookError.invalidNotebookCell(cell.id)
                }
            case .evidence:
                guard let id = cell.experimentID, let experiment = experimentByID[id],
                      cell.selectedEngines == experiment.engines.filter(Set(cell.selectedEngines).contains) else {
                    throw GrammarResearchNotebookError.invalidNotebookCell(cell.id)
                }
            }
        }
        let payload = GrammarResearchNotebook.FingerprintPayload(
            schemaVersion: value.schemaVersion,
            kind: value.kind,
            producer: value.producer,
            title: value.title,
            researchQuestion: value.researchQuestion,
            project: value.project,
            cells: value.cells,
            fingerprintAlgorithm: value.fingerprintAlgorithm
        )
        guard ResearchFingerprint.make(try canonicalEncoder().encode(payload)) == value.fingerprint else {
            throw GrammarResearchNotebookError.notebookFingerprintMismatch
        }
    }

    private static func canonical(_ value: String) -> Bool {
        !value.isEmpty && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum GrammarResearchNotebookError: Error, LocalizedError, Sendable {
    case artifactTooLarge
    case malformedProject
    case unsupportedProjectSchema(Int)
    case invalidProjectProducer
    case invalidProjectMetadata
    case invalidProjectEntries
    case malformedNotebook(String)
    case unsupportedNotebookSchema(Int)
    case invalidNotebookMetadata
    case invalidNotebookEvidence
    case invalidNotebookCell(String)
    case duplicateCellID
    case notebookFingerprintMismatch

    public var errorDescription: String? {
        switch self {
        case .artifactTooLarge: "The research artifact exceeds the Workbench safety limit."
        case .malformedProject: "The Grammar-REPL experiment project is malformed."
        case .unsupportedProjectSchema(let version):
            "Grammar-REPL experiment-project schema \(version) is not supported."
        case .invalidProjectProducer: "The project does not identify Grammar-REPL 0.9.0 or later."
        case .invalidProjectMetadata: "The experiment-project metadata or fingerprint declaration is invalid."
        case .invalidProjectEntries: "Experiment-project entries are not unique and canonical."
        case .malformedNotebook(let message): "The research notebook is malformed: \(message)"
        case .unsupportedNotebookSchema(let version): "Research-notebook schema \(version) is not supported."
        case .invalidNotebookMetadata: "Research-notebook metadata is invalid."
        case .invalidNotebookEvidence: "Research-notebook evidence references are invalid."
        case .invalidNotebookCell(let id): "Research-notebook cell \(id.debugDescription) is invalid."
        case .duplicateCellID: "Research-notebook cell identifiers must be unique."
        case .notebookFingerprintMismatch: "The research-notebook fingerprint does not match its contents."
        }
    }
}

private func canonicalEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
}
