import Foundation

public struct GrammarSourceProjectGrammar: Hashable, Codable, Sendable {
    public var path: String
    public var notation: GrammarSourceNotation
    public var algorithm: GrammarAlgorithm
    public var languageID: String

    public init(
        path: String,
        notation: GrammarSourceNotation = .workbench,
        algorithm: GrammarAlgorithm = .lalr,
        languageID: String
    ) {
        self.path = path
        self.notation = notation
        self.algorithm = algorithm
        self.languageID = languageID
    }
}

public struct GrammarSourceAssociation: Identifiable, Hashable, Codable, Sendable {
    public var pattern: String
    public var languageID: String
    public var id: String { "\(languageID):\(pattern)" }

    public init(pattern: String, languageID: String) {
        self.pattern = pattern
        self.languageID = languageID
    }

    public func matches(relativePath: String) -> Bool {
        guard let expression = try? NSRegularExpression(
            pattern: Self.regularExpression(for: pattern),
            options: [.caseInsensitive]
        ) else { return false }
        let range = NSRange(relativePath.startIndex..<relativePath.endIndex, in: relativePath)
        return expression.firstMatch(in: relativePath, range: range)?.range == range
    }

    private static func regularExpression(for glob: String) -> String {
        let characters = Array(glob)
        var result = "^"
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "*" {
                if index + 1 < characters.count, characters[index + 1] == "*" {
                    if index + 2 < characters.count, characters[index + 2] == "/" {
                        result += "(?:.*/)?"
                        index += 2
                    } else {
                        result += ".*"
                        index += 1
                    }
                } else {
                    result += "[^/]*"
                }
            } else if character == "?" {
                result += "[^/]"
            } else {
                result += NSRegularExpression.escapedPattern(for: String(character))
            }
            index += 1
        }
        return result + "$"
    }
}

/// A filesystem-facing project descriptor shared by the native application,
/// editor clients, and command-line automation. Unlike the portable project
/// manifest, it stores paths and glob associations rather than embedded text.
public struct GrammarSourceProjectDescriptor: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1
    public static let kindIdentifier = "grammar-workbench-source-project"
    public static let preferredFilename = ".grammar-workbench-source.json"

    public let schemaVersion: Int
    public let kind: String
    public let apiVersion: Int
    public var name: String
    public var grammar: GrammarSourceProjectGrammar
    public var associations: [GrammarSourceAssociation]
    public var semanticSchemaPath: String?

    public init(
        name: String,
        grammar: GrammarSourceProjectGrammar,
        associations: [GrammarSourceAssociation],
        semanticSchemaPath: String? = nil
    ) {
        schemaVersion = Self.currentSchemaVersion
        kind = Self.kindIdentifier
        apiVersion = GrammarWorkbenchAPI.version
        self.name = name
        self.grammar = grammar
        self.associations = associations
        self.semanticSchemaPath = semanticSchemaPath
    }
}

public enum GrammarSourceProjectError: Error, LocalizedError, Sendable {
    case unsupportedVersion(Int)
    case unsupportedAPIVersion(Int)
    case invalidKind(String)
    case emptyName
    case invalidLanguageID(String)
    case invalidPath(String)
    case invalidPattern(String)
    case duplicateAssociation(String)
    case unreadableUTF8(String)
    case noSources
    case tooManySources(Int)
    case sourceTooLarge(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let value): "Unsupported source-project schema version \(value)."
        case .unsupportedAPIVersion(let value): "Unsupported source-project API version \(value)."
        case .invalidKind(let value): "Unexpected source-project kind ‘\(value)’."
        case .emptyName: "A source project must have a name."
        case .invalidLanguageID(let value): "Language identifier ‘\(value)’ is invalid."
        case .invalidPath(let value): "Source-project path ‘\(value)’ is not a safe relative path."
        case .invalidPattern(let value): "Source association ‘\(value)’ is invalid."
        case .duplicateAssociation(let value): "Source association ‘\(value)’ is duplicated."
        case .unreadableUTF8(let value): "Project file ‘\(value)’ is not readable UTF-8 text."
        case .noSources: "No source files match the project associations."
        case .tooManySources(let value): "The project contains \(value) sources, exceeding the loading limit."
        case .sourceTooLarge(let value): "Project source ‘\(value)’ exceeds the loading-size limit."
        }
    }
}

public enum GrammarSourceProjectCodec {
    public static func encode(_ descriptor: GrammarSourceProjectDescriptor) throws -> Data {
        try validate(descriptor)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(descriptor)
    }

    public static func decode(_ data: Data) throws -> GrammarSourceProjectDescriptor {
        let descriptor = try JSONDecoder().decode(GrammarSourceProjectDescriptor.self, from: data)
        try validate(descriptor)
        return descriptor
    }

    public static func validate(_ descriptor: GrammarSourceProjectDescriptor) throws {
        guard descriptor.schemaVersion == GrammarSourceProjectDescriptor.currentSchemaVersion else {
            throw GrammarSourceProjectError.unsupportedVersion(descriptor.schemaVersion)
        }
        guard descriptor.apiVersion == GrammarWorkbenchAPI.version else {
            throw GrammarSourceProjectError.unsupportedAPIVersion(descriptor.apiVersion)
        }
        guard descriptor.kind == GrammarSourceProjectDescriptor.kindIdentifier else {
            throw GrammarSourceProjectError.invalidKind(descriptor.kind)
        }
        guard !descriptor.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GrammarSourceProjectError.emptyName
        }
        guard isLanguageID(descriptor.grammar.languageID) else {
            throw GrammarSourceProjectError.invalidLanguageID(descriptor.grammar.languageID)
        }
        try validatePath(descriptor.grammar.path)
        if let path = descriptor.semanticSchemaPath { try validatePath(path) }
        var identities: Set<String> = []
        for association in descriptor.associations {
            guard isLanguageID(association.languageID),
                  association.languageID == descriptor.grammar.languageID else {
                throw GrammarSourceProjectError.invalidLanguageID(association.languageID)
            }
            guard !association.pattern.isEmpty, !association.pattern.hasPrefix("/"),
                  !association.pattern.contains("\\"), !association.pattern.contains("\0"),
                  !association.pattern.split(separator: "/").contains("..") else {
                throw GrammarSourceProjectError.invalidPattern(association.pattern)
            }
            guard identities.insert(association.id.lowercased()).inserted else {
                throw GrammarSourceProjectError.duplicateAssociation(association.id)
            }
        }
        guard !descriptor.associations.isEmpty else {
            throw GrammarSourceProjectError.noSources
        }
    }

    private static func validatePath(_ path: String) throws {
        guard GrammarProjectCodec.isSafeRelativePath(path) else {
            throw GrammarSourceProjectError.invalidPath(path)
        }
    }

    private static func isLanguageID(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.")).contains($0)
        }
    }
}

public struct GrammarLoadedSourceProject: Sendable {
    public let descriptorURL: URL
    public let descriptor: GrammarSourceProjectDescriptor
    public let manifest: GrammarProjectManifest
    public let semanticSchema: GrammarSemanticWorkspaceSchema?
}

public enum GrammarSourceProjectLoader {
    public static let maximumSources = 4_096
    public static let maximumSourceBytes = 8 * 1_024 * 1_024

    public static func load(at descriptorURL: URL) throws -> GrammarLoadedSourceProject {
        let descriptor = try GrammarSourceProjectCodec.decode(Data(contentsOf: descriptorURL))
        let root = descriptorURL.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
        let grammarSource = try readUTF8(path: descriptor.grammar.path, beneath: root)
        let semanticSchema: GrammarSemanticWorkspaceSchema?
        if let path = descriptor.semanticSchemaPath {
            semanticSchema = try JSONDecoder().decode(
                GrammarSemanticWorkspaceSchema.self,
                from: data(path: path, beneath: root)
            )
        } else {
            semanticSchema = nil
        }

        let keys: [URLResourceKey] = [.isRegularFileKey, .isHiddenKey, .fileSizeKey]
        let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        var sources: [GrammarProjectSource] = []
        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true else { continue }
            let relative = relativePath(of: url.standardizedFileURL, beneath: root)
            guard relative != descriptor.grammar.path,
                  relative != descriptor.semanticSchemaPath,
                  descriptor.associations.contains(where: { $0.matches(relativePath: relative) }) else {
                continue
            }
            guard values.fileSize ?? 0 <= maximumSourceBytes else {
                throw GrammarSourceProjectError.sourceTooLarge(relative)
            }
            sources.append(.init(id: relative, path: relative, text: try readUTF8(path: relative, beneath: root)))
            guard sources.count <= maximumSources else {
                throw GrammarSourceProjectError.tooManySources(sources.count)
            }
        }
        guard !sources.isEmpty else { throw GrammarSourceProjectError.noSources }
        sources.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        let manifest = GrammarProjectManifest(
            name: descriptor.name,
            grammar: .init(
                source: grammarSource,
                notation: descriptor.grammar.notation,
                algorithm: descriptor.grammar.algorithm
            ),
            sources: sources
        )
        try GrammarProjectCodec.validate(manifest)
        return .init(
            descriptorURL: descriptorURL.standardizedFileURL,
            descriptor: descriptor,
            manifest: manifest,
            semanticSchema: semanticSchema
        )
    }

    private static func readUTF8(path: String, beneath root: URL) throws -> String {
        guard let value = String(data: try data(path: path, beneath: root), encoding: .utf8) else {
            throw GrammarSourceProjectError.unreadableUTF8(path)
        }
        return value
    }

    private static func data(path: String, beneath root: URL) throws -> Data {
        let url = root.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path == root.path || url.path.hasPrefix(root.path + "/") else {
            throw GrammarSourceProjectError.invalidPath(path)
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else {
            throw GrammarSourceProjectError.invalidPath(path)
        }
        guard values.fileSize ?? 0 <= maximumSourceBytes else {
            throw GrammarSourceProjectError.sourceTooLarge(path)
        }
        return try Data(contentsOf: url)
    }

    private static func relativePath(of url: URL, beneath root: URL) -> String {
        String(url.path.dropFirst(root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
