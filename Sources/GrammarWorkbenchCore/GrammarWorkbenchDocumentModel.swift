import Foundation

public struct WorkbenchSample: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var input: String

    public init(id: UUID = UUID(), name: String, input: String) {
        self.id = id
        self.name = name
        self.input = input
    }
}

public struct GrammarWorkbenchDocument: Codable, Sendable {
    public var source: String
    public var algorithm: String
    public var notation: GrammarSourceNotation
    public var samples: [WorkbenchSample]
    public var selectedSampleID: UUID
    public var tests: [WorkbenchTestCase]

    public init(
        source: String = Self.defaultSource,
        algorithm: String = "LALR(1)",
        notation: GrammarSourceNotation = .workbench,
        samples: [WorkbenchSample] = [
            WorkbenchSample(name: "Expression", input: "alpha + beta * gamma")
        ],
        selectedSampleID: UUID? = nil,
        tests: [WorkbenchTestCase] = [
            .init(name: "Valid expression", input: "alpha + beta * gamma", expectation: .accept),
            .init(name: "Missing operand", input: "alpha +", expectation: .reject)
        ]
    ) {
        let normalizedSamples = samples.isEmpty
            ? [WorkbenchSample(name: "Sample 1", input: "")]
            : samples
        self.source = source
        self.algorithm = algorithm
        self.notation = notation
        self.samples = normalizedSamples
        self.selectedSampleID = selectedSampleID.flatMap { selected in
            normalizedSamples.contains { $0.id == selected } ? selected : nil
        } ?? normalizedSamples[0].id
        self.tests = tests
    }

    private enum CodingKeys: String, CodingKey {
        case source, algorithm, notation, samples, selectedSampleID, tests
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            source: try values.decode(String.self, forKey: .source),
            algorithm: try values.decodeIfPresent(String.self, forKey: .algorithm) ?? "LALR(1)",
            notation: try values.decodeIfPresent(GrammarSourceNotation.self, forKey: .notation) ?? .workbench,
            samples: try values.decodeIfPresent([WorkbenchSample].self, forKey: .samples) ?? [],
            selectedSampleID: try values.decodeIfPresent(UUID.self, forKey: .selectedSampleID),
            tests: try values.decodeIfPresent([WorkbenchTestCase].self, forKey: .tests) ?? []
        )
    }

    public static let defaultSource = """
    %start E
    %token ID /[A-Za-z_][A-Za-z0-9_]*/
    %skip /\\s+/
    %left '+'
    %left '*'

    E : E '+' E
      | E '*' E
      | ID
      ;
    """
}
