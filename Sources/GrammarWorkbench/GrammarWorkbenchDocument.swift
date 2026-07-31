import SwiftUI
import UniformTypeIdentifiers

public extension UTType {
    static let grammarWorkbenchDocument = UTType(
        exportedAs: "com.grammar-workbench.document",
        conformingTo: .json
    )
}

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

public struct GrammarWorkbenchDocument: FileDocument, Codable, Sendable {
    public static let readableContentTypes: [UTType] = [.grammarWorkbenchDocument, .plainText]
    public static let writableContentTypes: [UTType] = [.grammarWorkbenchDocument, .plainText]

    public var source: String
    public var algorithm: String
    public var samples: [WorkbenchSample]
    public var selectedSampleID: UUID

    public init(
        source: String = Self.defaultSource,
        algorithm: String = "LALR(1)",
        samples: [WorkbenchSample] = [
            WorkbenchSample(name: "Expression", input: "alpha + beta * gamma")
        ],
        selectedSampleID: UUID? = nil
    ) {
        let normalizedSamples = samples.isEmpty
            ? [WorkbenchSample(name: "Sample 1", input: "")]
            : samples
        self.source = source
        self.algorithm = algorithm
        self.samples = normalizedSamples
        self.selectedSampleID = selectedSampleID.flatMap { selected in
            normalizedSamples.contains { $0.id == selected } ? selected : nil
        } ?? normalizedSamples[0].id
    }

    public init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if configuration.contentType == .grammarWorkbenchDocument,
           let decoded = try? JSONDecoder().decode(Self.self, from: data) {
            self = Self(
                source: decoded.source,
                algorithm: decoded.algorithm,
                samples: decoded.samples,
                selectedSampleID: decoded.selectedSampleID
            )
        } else {
            guard let source = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            self = Self(source: source, samples: [WorkbenchSample(name: "Sample 1", input: "")])
        }
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        if configuration.contentType == .plainText {
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
            .frame(minWidth: 1120, minHeight: 720)
    }
}
