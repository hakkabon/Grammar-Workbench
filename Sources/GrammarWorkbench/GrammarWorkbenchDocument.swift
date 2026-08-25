#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
#endif
import Foundation

#if os(macOS)
public extension UTType {
    static let grammarWorkbenchDocument = UTType(
        exportedAs: "com.grammar-workbench.document",
        conformingTo: .json
    )
    static let ebnfGrammar = UTType(
        importedAs: "org.iso.ebnf-source",
        conformingTo: .plainText
    )
}
#endif

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

#if os(macOS)
public struct GrammarWorkbenchDocument: FileDocument, Codable, Sendable {
    public static let readableContentTypes: [UTType] = [.grammarWorkbenchDocument, .ebnfGrammar, .plainText]
    public static let writableContentTypes: [UTType] = [.grammarWorkbenchDocument, .ebnfGrammar, .plainText]

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

    public init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try self.init(fileData: data, contentType: configuration.contentType)
    }

    init(fileData data: Data, contentType: UTType) throws {
        if contentType == .grammarWorkbenchDocument,
           let decoded = try? JSONDecoder().decode(Self.self, from: data) {
            self = Self(
                source: decoded.source,
                algorithm: decoded.algorithm,
                notation: decoded.notation,
                samples: decoded.samples,
                selectedSampleID: decoded.selectedSampleID,
                tests: decoded.tests
            )
        } else {
            guard let source = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            self = Self(
                source: source,
                notation: contentType == .ebnfGrammar
                    ? .ebnf
                    : GrammarSourceNotationDetector.detect(source: source),
                samples: [WorkbenchSample(name: "Sample 1", input: "")]
            )
        }
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        if configuration.contentType == .plainText || configuration.contentType == .ebnfGrammar {
            return FileWrapper(regularFileWithContents: Data(source.utf8))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(self))
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

public struct GrammarWorkbenchView: View {
    @Binding private var document: GrammarWorkbenchDocument
    private let documentName: String

    public init(document: Binding<GrammarWorkbenchDocument>, documentName: String = "Untitled") {
        self._document = document
        self.documentName = documentName
    }

    public var body: some View {
        ArtifactExplorerView(document: $document, documentName: documentName)
            .frame(
                minWidth: WorkbenchVisualFoundation.windowMinimumWidth,
                minHeight: WorkbenchVisualFoundation.windowMinimumHeight
            )
    }
}
#endif
