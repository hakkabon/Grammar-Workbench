import Foundation

public enum WorkbenchTestExpectation: String, CaseIterable, Codable, Identifiable, Sendable {
    case accept = "Accept"
    case reject = "Reject"
    case conflict = "Conflict"
    public var id: Self { self }
}

public struct WorkbenchTestCase: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var input: String
    public var expectation: WorkbenchTestExpectation
    public var expectedTree: String?

    public init(
        id: UUID = UUID(),
        name: String,
        input: String,
        expectation: WorkbenchTestExpectation,
        expectedTree: String? = nil
    ) {
        self.id = id
        self.name = name
        self.input = input
        self.expectation = expectation
        self.expectedTree = expectedTree
    }
}

public enum WorkbenchTestStatus: String, Codable, Sendable {
    case passed
    case failed
    case invalid
}

public struct WorkbenchTestResult: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let status: WorkbenchTestStatus
    public let expected: WorkbenchTestExpectation
    public let actual: String
    public let message: String
    public let tokens: [String]
    public let tree: String?
}

public struct WorkbenchTestReport: Sendable {
    public let results: [WorkbenchTestResult]
    public var passed: Int { results.count { $0.status == .passed } }
    public var failed: Int { results.count { $0.status != .passed } }
    public var allPassed: Bool { !results.isEmpty && failed == 0 }
}

public enum GrammarTestRunner {
    public static func run(
        _ tests: [WorkbenchTestCase],
        source: String,
        algorithm: String = "LALR(1)",
        notation: GrammarSourceNotation = .workbench
    ) -> WorkbenchTestReport {
        let frontEnd = GrammarFrontEnd.process(source, notation: notation)
        guard let grammar = frontEnd.grammar, let analysis = frontEnd.analysis,
              let selectedAlgorithm = LRAlgorithm(rawValue: algorithm) else {
            let message = frontEnd.diagnostics.first(where: { $0.severity == .error })?.message
                ?? "Unknown LR algorithm ‘\(algorithm)’."
            return .init(results: tests.map {
                .init(id: $0.id, name: $0.name, status: .invalid, expected: $0.expectation,
                      actual: "Not run", message: message, tokens: [], tree: nil)
            })
        }
        let artifact = LRConstructionEngine.construct(
            grammar: grammar, analysis: analysis, source: source, algorithm: selectedAlgorithm
        )
        return run(tests, grammar: grammar, artifact: artifact)
    }

    static func run(
        _ tests: [WorkbenchTestCase],
        grammar: ParsedGrammar,
        artifact: GrammarArtifact
    ) -> WorkbenchTestReport {
        .init(results: tests.map { test in
            let tokens: [String]
            if !grammar.lexerRules.isEmpty {
                let lexed = GrammarLexerRuntime.lex(test.input, grammar: grammar)
                if let diagnostic = lexed.diagnostics.first {
                    return WorkbenchTestResult(
                        id: test.id, name: test.name, status: .failed, expected: test.expectation,
                        actual: "Lexical error", message: "\(diagnostic.range.start.line):\(diagnostic.range.start.column): \(diagnostic.message)",
                        tokens: lexed.tokens.map(\.kind), tree: nil
                    )
                }
                tokens = lexed.tokens.map(\.kind)
            } else {
                switch SampleInputTokenizer.tokenize(test.input) {
                case .success(let values): tokens = values
                case .failure(let error):
                    return WorkbenchTestResult(
                        id: test.id, name: test.name, status: .failed, expected: test.expectation,
                        actual: "Tokenization error", message: error.message, tokens: [], tree: nil
                    )
                }
            }
            let runtime = LRParserRuntime.parse(tokens, artifact: artifact)
            let actualExpectation: WorkbenchTestExpectation?
            switch runtime.outcome {
            case .accepted: actualExpectation = .accept
            case .rejected: actualExpectation = .reject
            case .conflict: actualExpectation = .conflict
            case .looping: actualExpectation = nil
            }
            let tree = runtime.tree?.rendered()
            let outcomeMatches = actualExpectation == test.expectation
            let expectedTree = test.expectedTree?.trimmingCharacters(in: .whitespacesAndNewlines)
            let treeMatches = expectedTree?.isEmpty != false || tree == expectedTree
            let status: WorkbenchTestStatus = outcomeMatches && treeMatches ? .passed : .failed
            let message: String
            if !outcomeMatches {
                message = "Expected \(test.expectation.rawValue.lowercased()), got \(runtime.outcome.label)."
            } else if !treeMatches {
                message = "The parse outcome matched, but the parse tree differs from the snapshot."
            } else {
                message = "Expectation matched."
            }
            return .init(
                id: test.id, name: test.name, status: status, expected: test.expectation,
                actual: runtime.outcome.label, message: message, tokens: tokens, tree: tree
            )
        })
    }
}

public struct GrammarWorkbenchInterchange: Codable, Sendable {
    public static let currentSchemaVersion = 2
    public let schemaVersion: Int
    public let source: String
    public let algorithm: String
    public let notation: GrammarSourceNotation
    public let samples: [WorkbenchSample]
    public let selectedSampleID: UUID
    public let tests: [WorkbenchTestCase]

    public init(document: GrammarWorkbenchDocument) {
        schemaVersion = Self.currentSchemaVersion
        source = document.source
        algorithm = document.algorithm
        notation = document.notation
        samples = document.samples
        selectedSampleID = document.selectedSampleID
        tests = document.tests
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, source, algorithm, notation, samples, selectedSampleID, tests
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        source = try values.decode(String.self, forKey: .source)
        algorithm = try values.decode(String.self, forKey: .algorithm)
        notation = try values.decodeIfPresent(GrammarSourceNotation.self, forKey: .notation) ?? .workbench
        samples = try values.decode([WorkbenchSample].self, forKey: .samples)
        selectedSampleID = try values.decode(UUID.self, forKey: .selectedSampleID)
        tests = try values.decodeIfPresent([WorkbenchTestCase].self, forKey: .tests) ?? []
    }
}

/// Public envelope for exchange with build tools, visualizers, and parser
/// generators that do not link the construction engine.
public struct GrammarArtifactInterchange: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 2
    public static let kindIdentifier = "grammar-workbench-artifact"

    public let schemaVersion: Int
    public let kind: String
    public let producer: String
    public let generatedAt: Date
    public let artifact: GrammarArtifactSnapshot

    public init(
        artifact: GrammarArtifactSnapshot,
        producer: String = "Grammar Workbench \(GrammarWorkbenchRelease.version)",
        generatedAt: Date = Date()
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.kind = Self.kindIdentifier
        self.producer = producer
        self.generatedAt = generatedAt
        self.artifact = artifact
    }
}

public enum GrammarInterchangeError: Error, LocalizedError {
    case unsupportedVersion(Int)
    case unsupportedAPIVersion(Int)
    case invalidKind(String)
    case invalidAlgorithm(String)
    case invalidGrammar(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "Unsupported interchange schema version \(version)."
        case .unsupportedAPIVersion(let version): "Unsupported artifact API version \(version)."
        case .invalidKind(let kind): "Unexpected interchange document kind ‘\(kind)’."
        case .invalidAlgorithm(let value): "Unknown LR algorithm ‘\(value)’ in interchange data."
        case .invalidGrammar(let message): "The imported grammar is invalid: \(message)"
        }
    }
}

public enum GrammarInterchangeCodec {
    private struct InterchangeHeader: Decodable {
        let schemaVersion: Int
    }

    private struct LegacyArtifactInterchange: Decodable {
        let schemaVersion: Int
        let kind: String
        let generatedAt: Date
        let artifact: GrammarArtifact
    }

    public static func encode(_ document: GrammarWorkbenchDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(GrammarWorkbenchInterchange(document: document))
    }

    public static func encodeArtifact(
        source: String,
        algorithm: String = "LALR(1)",
        notation: GrammarSourceNotation = .workbench
    ) throws -> Data {
        guard let selectedAlgorithm = GrammarAlgorithm(rawValue: algorithm) else {
            throw GrammarInterchangeError.invalidAlgorithm(algorithm)
        }
        return try encodeArtifact(compilation: GrammarWorkbenchAPI.compile(.init(
            source: source, algorithm: selectedAlgorithm, notation: notation
        )))
    }

    public static func encodeArtifact(
        compilation: GrammarCompilation,
        generatedAt: Date = Date()
    ) throws -> Data {
        guard let artifact = compilation.artifact else {
            throw GrammarInterchangeError.invalidGrammar(
                compilation.diagnostics.first(where: { $0.severity == .error })?.message
                    ?? "Unknown grammar error."
            )
        }
        let envelope = GrammarArtifactInterchange(artifact: artifact, generatedAt: generatedAt)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(envelope)
    }

    public static func decodeArtifact(_ data: Data) throws -> GrammarArtifactInterchange {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let header = try decoder.decode(InterchangeHeader.self, from: data)
        if header.schemaVersion == 1 {
            let legacy = try decoder.decode(LegacyArtifactInterchange.self, from: data)
            guard legacy.kind == GrammarArtifactInterchange.kindIdentifier else {
                throw GrammarInterchangeError.invalidKind(legacy.kind)
            }
            return GrammarArtifactInterchange(
                artifact: GrammarArtifactSnapshot(legacy.artifact),
                producer: "Grammar Workbench (legacy interchange)",
                generatedAt: legacy.generatedAt
            )
        }
        let value = try decoder.decode(GrammarArtifactInterchange.self, from: data)
        guard value.schemaVersion == GrammarArtifactInterchange.currentSchemaVersion else {
            throw GrammarInterchangeError.unsupportedVersion(value.schemaVersion)
        }
        guard value.kind == GrammarArtifactInterchange.kindIdentifier else {
            throw GrammarInterchangeError.invalidKind(value.kind)
        }
        guard value.artifact.apiVersion == GrammarWorkbenchAPI.version else {
            throw GrammarInterchangeError.unsupportedAPIVersion(value.artifact.apiVersion)
        }
        return value
    }

    public static func decode(_ data: Data) throws -> GrammarWorkbenchDocument {
        let value = try JSONDecoder().decode(GrammarWorkbenchInterchange.self, from: data)
        guard (1...GrammarWorkbenchInterchange.currentSchemaVersion).contains(value.schemaVersion) else {
            throw GrammarInterchangeError.unsupportedVersion(value.schemaVersion)
        }
        guard LRAlgorithm(rawValue: value.algorithm) != nil else {
            throw GrammarInterchangeError.invalidAlgorithm(value.algorithm)
        }
        let result = GrammarFrontEnd.process(value.source, notation: value.notation)
        if let diagnostic = result.diagnostics.first(where: { $0.severity == .error }) {
            throw GrammarInterchangeError.invalidGrammar(diagnostic.message)
        }
        return GrammarWorkbenchDocument(
            source: value.source, algorithm: value.algorithm, notation: value.notation, samples: value.samples,
            selectedSampleID: value.selectedSampleID, tests: value.tests
        )
    }
}
