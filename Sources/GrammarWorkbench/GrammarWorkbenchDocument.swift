#if canImport(SwiftUI)
import SwiftUI
import UniformTypeIdentifiers
#endif
import Foundation

#if canImport(SwiftUI)
public extension UTType {
    static let grammarWorkbenchDocument = UTType(
        exportedAs: "com.grammar-workbench.document",
        conformingTo: .json
    )
    static let ebnfGrammar = UTType(
        importedAs: "org.iso.ebnf-source",
        conformingTo: .plainText
    )
    static let bnfGrammar = UTType(
        importedAs: "org.iso.bnf-source",
        conformingTo: .plainText
    )
    static let yaccGrammar = UTType(
        importedAs: "com.grammar-workbench.yacc-source",
        conformingTo: .plainText
    )
}
#endif

import GrammarWorkbenchCore

#if canImport(SwiftUI)
extension GrammarWorkbenchDocument: FileDocument {
    public static let readableContentTypes: [UTType] = [
        .grammarWorkbenchDocument, .ebnfGrammar, .bnfGrammar, .yaccGrammar, .plainText
    ]
    public static let writableContentTypes: [UTType] = [
        .grammarWorkbenchDocument, .ebnfGrammar, .bnfGrammar, .yaccGrammar, .plainText
    ]

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
                notation: contentType == .ebnfGrammar || contentType == .bnfGrammar
                    ? .ebnf
                    : GrammarSourceNotationDetector.detect(source: source),
                samples: [WorkbenchSample(name: "Sample 1", input: "")]
            )
        }
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        if configuration.contentType != .grammarWorkbenchDocument {
            return FileWrapper(regularFileWithContents: Data(source.utf8))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(self))
    }
}

public struct GrammarWorkbenchView: View {
    @Binding private var document: GrammarWorkbenchDocument
    private let documentName: String

    public init(document: Binding<GrammarWorkbenchDocument>, documentName: String = "Untitled") {
        self._document = document
        self.documentName = documentName
    }

    public var body: some View {
#if os(macOS)
        ArtifactExplorerView(document: $document, documentName: documentName)
            .frame(
                minWidth: WorkbenchVisualFoundation.windowMinimumWidth,
                minHeight: WorkbenchVisualFoundation.windowMinimumHeight
            )
#elseif os(iOS)
        GrammarWorkbenchTabletView(document: $document, documentName: documentName)
#endif
    }
}
#endif
