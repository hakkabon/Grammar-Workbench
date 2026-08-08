import Foundation

public struct GrammarGeneratorOptionDescriptor: Hashable, Codable, Sendable {
    public let name: String
    public let summary: String
    public let defaultValue: String?
    public let allowedValues: [String]

    public init(
        name: String,
        summary: String,
        defaultValue: String? = nil,
        allowedValues: [String] = []
    ) {
        self.name = name
        self.summary = summary
        self.defaultValue = defaultValue
        self.allowedValues = allowedValues
    }
}

public struct GrammarGeneratorDescriptor: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let displayName: String
    public let summary: String
    public let defaultFileExtension: String
    public let mediaType: String
    public let options: [GrammarGeneratorOptionDescriptor]

    public init(
        id: String,
        displayName: String,
        summary: String,
        defaultFileExtension: String,
        mediaType: String,
        options: [GrammarGeneratorOptionDescriptor] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.summary = summary
        self.defaultFileExtension = defaultFileExtension
        self.mediaType = mediaType
        self.options = options
    }
}

/// String-valued options keep the extension boundary stable for generators
/// supplied by host applications, packages, or command-line integrations.
public struct GrammarGeneratorOptions: Hashable, Codable, Sendable {
    public var values: [String: String]

    public init(_ values: [String: String] = [:]) {
        self.values = values
    }

    public subscript(_ key: String) -> String? {
        get { values[key] }
        set { values[key] = newValue }
    }
}

public struct GrammarGeneratedFile: Hashable, Codable, Sendable {
    public let suggestedFilename: String
    public let mediaType: String
    public let contents: Data

    public init(suggestedFilename: String, mediaType: String, contents: Data) {
        self.suggestedFilename = suggestedFilename
        self.mediaType = mediaType
        self.contents = contents
    }

    public init(suggestedFilename: String, mediaType: String, text: String) {
        self.init(suggestedFilename: suggestedFilename, mediaType: mediaType, contents: Data(text.utf8))
    }

    public var text: String? { String(data: contents, encoding: .utf8) }
}

public struct GrammarGenerationResult: Hashable, Codable, Sendable {
    public let generator: GrammarGeneratorDescriptor
    public let files: [GrammarGeneratedFile]
    public let diagnostics: [String]

    public init(
        generator: GrammarGeneratorDescriptor,
        files: [GrammarGeneratedFile],
        diagnostics: [String] = []
    ) {
        self.generator = generator
        self.files = files
        self.diagnostics = diagnostics
    }
}

public protocol GrammarGenerator: Sendable {
    var descriptor: GrammarGeneratorDescriptor { get }
    func generate(
        from compilation: GrammarCompilation,
        options: GrammarGeneratorOptions
    ) throws -> GrammarGenerationResult
}

public enum GrammarGeneratorRegistryError: Error, LocalizedError, Sendable {
    case duplicateIdentifier(String)
    case unknownGenerator(String)
    case compilationFailed(String)
    case unknownOption(String)
    case invalidOption(name: String, value: String)
    case emptyResult(String)
    case invalidFilename(String)
    case duplicateFilename(String)

    public var errorDescription: String? {
        switch self {
        case .duplicateIdentifier(let id): "A grammar generator named ‘\(id)’ is already registered."
        case .unknownGenerator(let id): "No grammar generator named ‘\(id)’ is registered."
        case .compilationFailed(let message): "Generation requires a valid grammar: \(message)"
        case .invalidOption(let name, let value): "Invalid value ‘\(value)’ for generator option ‘\(name)’."
        case .emptyResult(let id): "Generator ‘\(id)’ did not produce any files."
        case .unknownOption(let name): "Unknown generator option ‘\(name)’."
        case .invalidFilename(let name): "Generator output filename ‘\(name)’ is not a safe leaf filename."
        case .duplicateFilename(let name): "Generator produced the output filename ‘\(name)’ more than once."
        }
    }
}

/// A concurrency-safe extension point. Registry instances are independent, so
/// Xcode hosts can install application-specific generators without global state.
public actor GrammarGeneratorRegistry {
    private var generators: [String: any GrammarGenerator]

    public init(includingBuiltIns: Bool = true) {
        if includingBuiltIns {
            let builtIns: [any GrammarGenerator] = [
                SwiftGrammarGenerator(), BNFGrammarGenerator(), ArtifactJSONGrammarGenerator(),
                SemanticModelJSONGrammarGenerator(), SwiftSemanticActionsGrammarGenerator()
            ]
            self.generators = Dictionary(uniqueKeysWithValues: builtIns.map { ($0.descriptor.id, $0) })
        } else {
            self.generators = [:]
        }
    }

    public func register(_ generator: any GrammarGenerator, replacingExisting: Bool = false) throws {
        let id = generator.descriptor.id
        if generators[id] != nil, !replacingExisting {
            throw GrammarGeneratorRegistryError.duplicateIdentifier(id)
        }
        generators[id] = generator
    }

    @discardableResult
    public func unregister(identifier: String) -> Bool {
        generators.removeValue(forKey: identifier) != nil
    }

    public func availableGenerators() -> [GrammarGeneratorDescriptor] {
        generators.values.map(\.descriptor).sorted { $0.id < $1.id }
    }

    public func generate(
        identifier: String,
        from compilation: GrammarCompilation,
        options: GrammarGeneratorOptions = .init()
    ) async throws -> GrammarGenerationResult {
        guard let generator = generators[identifier] else {
            throw GrammarGeneratorRegistryError.unknownGenerator(identifier)
        }
        let declaredOptions = Dictionary(
            generator.descriptor.options.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for (name, value) in options.values {
            guard let declaration = declaredOptions[name] else {
                throw GrammarGeneratorRegistryError.unknownOption(name)
            }
            if !declaration.allowedValues.isEmpty,
               !declaration.allowedValues.contains(value) {
                throw GrammarGeneratorRegistryError.invalidOption(name: name, value: value)
            }
        }
        let result = try await Task.detached(priority: .userInitiated) {
            try generator.generate(from: compilation, options: options)
        }.value
        guard !result.files.isEmpty else { throw GrammarGeneratorRegistryError.emptyResult(identifier) }
        var filenames: Set<String> = []
        for file in result.files {
            let filename = file.suggestedFilename
            guard !filename.isEmpty, filename != ".", filename != "..",
                  !filename.contains("/"), !filename.contains("\\"), !filename.contains("\0") else {
                throw GrammarGeneratorRegistryError.invalidFilename(filename)
            }
            guard filenames.insert(filename.lowercased()).inserted else {
                throw GrammarGeneratorRegistryError.duplicateFilename(filename)
            }
        }
        return result
    }
}

/// Generates a compiling, coverage-complete starting point for application
/// semantics. Each production has a distinct edit site and its identity is
/// documented alongside the readable rule.
public struct SwiftSemanticActionsGrammarGenerator: GrammarGenerator {
    public let descriptor = GrammarGeneratorDescriptor(
        id: "semantic-swift",
        displayName: "Swift Semantic Actions",
        summary: "A declarative, coverage-checkable Swift semantic reducer starter.",
        defaultFileExtension: "swift",
        mediaType: "text/x-swift",
        options: [
            .init(name: "typeName", summary: "Generated namespace name.", defaultValue: "GrammarSemantics")
        ]
    )

    public init() {}

    public func generate(
        from compilation: GrammarCompilation,
        options: GrammarGeneratorOptions
    ) throws -> GrammarGenerationResult {
        let model = try GrammarSemanticModel(compilation: compilation)
        let typeName = options["typeName"] ?? "GrammarSemantics"
        guard isSwiftIdentifier(typeName) else {
            throw GrammarGeneratorRegistryError.invalidOption(name: "typeName", value: typeName)
        }
        let actions = model.productions.map { production in
            let rule = production.text.replacingOccurrences(of: "*/", with: "* /")
            return """
                    // \(production.id): \(rule)
                    .init(\(production.id)) { reduction in
                        // Replace this default fold with the AST or semantic value for this rule.
                        reduction.children.joined()
                    }
            """
        }.joined(separator: ",\n")
        let source = """
        // Generated by Grammar Workbench. Safe to edit.
        import GrammarWorkbench

        public enum \(typeName) {
            public static func make() throws -> GrammarSemanticActions<String> {
                try GrammarSemanticActions(
                    terminal: { token, _ in token.lexeme },
                    missing: { symbol, _ in "<missing \\(symbol)>" },
                    productions: [
        \(actions)
                    ]
                )
            }

            public static func validate(for compilation: GrammarCompilation) throws {
                try GrammarSemanticModel(compilation: compilation).validate(make())
            }
        }
        """
        return .init(generator: descriptor, files: [
            .init(suggestedFilename: "\(typeName).swift", mediaType: descriptor.mediaType, text: source)
        ])
    }
}

public struct SemanticModelJSONGrammarGenerator: GrammarGenerator {
    public let descriptor = GrammarGeneratorDescriptor(
        id: "semantic-model-json",
        displayName: "Semantic Model JSON",
        summary: "Tool-neutral symbols and production identities for AST and language tooling.",
        defaultFileExtension: "semantic.json",
        mediaType: "application/json"
    )

    public init() {}

    public func generate(
        from compilation: GrammarCompilation,
        options: GrammarGeneratorOptions
    ) throws -> GrammarGenerationResult {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(GrammarSemanticModel(compilation: compilation))
        return .init(
            generator: descriptor,
            files: [.init(suggestedFilename: "Grammar.semantic.json", mediaType: descriptor.mediaType, contents: data)]
        )
    }
}

public struct SwiftGrammarGenerator: GrammarGenerator {
    public let descriptor = GrammarGeneratorDescriptor(
        id: "swift", displayName: "Standalone Swift Parser",
        summary: "A dependency-free table-driven Swift lexer and parser.",
        defaultFileExtension: "swift", mediaType: "text/x-swift",
        options: [
            .init(name: "typeName", summary: "Generated Swift type name.", defaultValue: "GeneratedParser"),
            .init(name: "accessLevel", summary: "Declaration access level.", defaultValue: "public", allowedValues: SwiftParserAccessLevel.allCases.map(\.rawValue)),
            .init(name: "conflictPolicy", summary: "Unresolved-conflict policy.", defaultValue: "fail", allowedValues: SwiftParserConflictPolicy.allCases.map(\.rawValue))
        ]
    )

    public init() {}

    public func generate(
        from compilation: GrammarCompilation,
        options: GrammarGeneratorOptions
    ) throws -> GrammarGenerationResult {
        let typeName = options["typeName"] ?? "GeneratedParser"
        let access = try option(options, key: "accessLevel", as: SwiftParserAccessLevel.self) ?? .public
        let conflicts = try option(options, key: "conflictPolicy", as: SwiftParserConflictPolicy.self) ?? .fail
        let source = try compilation.generateSwiftParser(options: .init(
            typeName: typeName, accessLevel: access, conflictPolicy: conflicts
        ))
        return .init(generator: descriptor, files: [
            .init(suggestedFilename: "\(typeName).swift", mediaType: descriptor.mediaType, text: source)
        ])
    }
}

public struct BNFGrammarGenerator: GrammarGenerator {
    public let descriptor = GrammarGeneratorDescriptor(
        id: "bnf", displayName: "Portable BNF",
        summary: "A tool-neutral BNF representation of the compiled grammar.",
        defaultFileExtension: "bnf", mediaType: "text/plain",
        options: [.init(name: "name", summary: "Suggested output base name.", defaultValue: "grammar")]
    )

    public init() {}

    public func generate(
        from compilation: GrammarCompilation,
        options: GrammarGeneratorOptions
    ) throws -> GrammarGenerationResult {
        guard compilation.succeeded, let grammar = compilation.grammar else {
            throw invalidCompilation(compilation)
        }
        let groups = Dictionary(grouping: grammar.productions, by: \.lhs)
        let orderedLHS = grammar.productions.map(\.lhs).reduce(into: [String]()) {
            if !$0.contains($1) { $0.append($1) }
        }
        let lines = orderedLHS.map { lhs in
            let alternatives = (groups[lhs] ?? []).map { production in
                production.rhs.isEmpty ? "ε" : production.rhs.map { symbol in
                    grammar.nonterminals.contains(symbol) ? "<\(symbol)>" : quotedBNFSymbol(symbol)
                }.joined(separator: " ")
            }
            return "<\(lhs)> ::= \(alternatives.joined(separator: "\n    | "))"
        }
        let name = options["name"] ?? "grammar"
        let text = "# Generated by Grammar Workbench\n# Start symbol: <\(grammar.startSymbol)>\n\n" + lines.joined(separator: "\n\n") + "\n"
        return .init(generator: descriptor, files: [
            .init(suggestedFilename: "\(name).bnf", mediaType: descriptor.mediaType, text: text)
        ], diagnostics: compilation.lexerAnalysis == nil ? [] : [
            "BNF describes parser productions only; lexer modes and patterns remain in artifact JSON."
        ])
    }
}

public struct ArtifactJSONGrammarGenerator: GrammarGenerator {
    public let descriptor = GrammarGeneratorDescriptor(
        id: "artifact-json", displayName: "Artifact Interchange JSON",
        summary: "The versioned, engine-independent parser artifact envelope.",
        defaultFileExtension: "json", mediaType: "application/json",
        options: [.init(name: "filename", summary: "Suggested output filename.", defaultValue: "grammar-artifact.json")]
    )

    public init() {}

    public func generate(
        from compilation: GrammarCompilation,
        options: GrammarGeneratorOptions
    ) throws -> GrammarGenerationResult {
        let data = try GrammarInterchangeCodec.encodeArtifact(compilation: compilation)
        return .init(generator: descriptor, files: [
            .init(suggestedFilename: options["filename"] ?? "grammar-artifact.json",
                  mediaType: descriptor.mediaType, contents: data)
        ])
    }
}

private func option<T: RawRepresentable>(
    _ options: GrammarGeneratorOptions, key: String, as type: T.Type
) throws -> T? where T.RawValue == String {
    guard let value = options[key] else { return nil }
    guard let parsed = T(rawValue: value) else {
        throw GrammarGeneratorRegistryError.invalidOption(name: key, value: value)
    }
    return parsed
}

private func invalidCompilation(_ compilation: GrammarCompilation) -> GrammarGeneratorRegistryError {
    .compilationFailed(
        compilation.diagnostics.first(where: { $0.severity == .error })?.message
            ?? "The grammar did not compile."
    )
}

private func quotedBNFSymbol(_ symbol: String) -> String {
    "\"" + symbol.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"") + "\""
}

private func isSwiftIdentifier(_ value: String) -> Bool {
    guard let first = value.unicodeScalars.first,
          CharacterSet.letters.union(CharacterSet(charactersIn: "_")).contains(first) else { return false }
    return value.unicodeScalars.dropFirst().allSatisfy {
        CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_")).contains($0)
    }
}
