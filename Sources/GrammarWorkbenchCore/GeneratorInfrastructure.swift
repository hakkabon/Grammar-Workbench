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
                SemanticModelJSONGrammarGenerator(), SwiftSemanticActionsGrammarGenerator(),
                BrowserPortableRuntimeGrammarGenerator(), LanguageDocumentationGrammarGenerator()
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

// MARK: - Public Workbench extensions

/// Versioning for the declarative extension boundary. This is intentionally
/// independent of the artifact, project, and tooling-service wire schemas.
public enum GrammarWorkbenchExtensionContract {
    public static let schemaVersion = 1
}

public enum GrammarExtensionCommandKind: String, CaseIterable, Codable, Sendable {
    /// Inspects a compilation and reports findings without changing it.
    case analysis
    /// Produces portable files that are not source-code generator products.
    case export
    /// Runs an opt-in, reproducible research or comparison operation.
    case research
}

public struct GrammarExtensionOptionDescriptor: Hashable, Codable, Sendable {
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

public struct GrammarExtensionCommandDescriptor: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let displayName: String
    public let summary: String
    public let kind: GrammarExtensionCommandKind
    public let options: [GrammarExtensionOptionDescriptor]

    public init(
        id: String,
        displayName: String,
        summary: String,
        kind: GrammarExtensionCommandKind,
        options: [GrammarExtensionOptionDescriptor] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.summary = summary
        self.kind = kind
        self.options = options
    }
}

/// Portable metadata used for discovery before any extension code is run.
/// Extension identifiers are reverse-domain names and versions use three-part
/// semantic versions, keeping registration deterministic across hosts.
public struct GrammarWorkbenchExtensionManifest: Identifiable, Hashable, Codable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public let displayName: String
    public let version: String
    public let summary: String
    public let minimumHostAPIVersion: Int
    public let commands: [GrammarExtensionCommandDescriptor]

    public init(
        schemaVersion: Int = GrammarWorkbenchExtensionContract.schemaVersion,
        id: String,
        displayName: String,
        version: String,
        summary: String,
        minimumHostAPIVersion: Int = GrammarWorkbenchAPIVersion.current,
        commands: [GrammarExtensionCommandDescriptor]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.displayName = displayName
        self.version = version
        self.summary = summary
        self.minimumHostAPIVersion = minimumHostAPIVersion
        self.commands = commands
    }
}

/// An immutable, engine-neutral view of a compilation. Extensions cannot
/// obtain the Workbench's private LR construction or runtime values through
/// this context.
public struct GrammarExtensionContext: Hashable, Codable, Sendable {
    public let hostAPIVersion: Int
    public let request: GrammarCompilationRequest
    public let succeeded: Bool
    public let diagnostics: [GrammarDiagnostic]
    public let grammar: GrammarSummary?
    public let analysis: GrammarAnalysisSnapshot?
    public let lexerAnalysis: LexerModeAnalysis?
    public let artifact: GrammarArtifactSnapshot?
    public let performance: GrammarConstructionPerformance

    public init(compilation: GrammarCompilation) {
        hostAPIVersion = compilation.apiVersion
        request = compilation.request
        succeeded = compilation.succeeded
        diagnostics = compilation.diagnostics
        grammar = compilation.grammar
        analysis = compilation.analysis
        lexerAnalysis = compilation.lexerAnalysis
        artifact = compilation.artifact
        performance = compilation.performance
    }
}

public struct GrammarExtensionOptions: Hashable, Codable, Sendable {
    public var values: [String: String]

    public init(_ values: [String: String] = [:]) {
        self.values = values
    }

    public subscript(_ key: String) -> String? {
        get { values[key] }
        set { values[key] = newValue }
    }
}

public struct GrammarExtensionRequest: Hashable, Codable, Sendable {
    public let extensionIdentifier: String
    public let commandIdentifier: String
    public let context: GrammarExtensionContext
    public let options: GrammarExtensionOptions

    public init(
        extensionIdentifier: String,
        commandIdentifier: String,
        context: GrammarExtensionContext,
        options: GrammarExtensionOptions = .init()
    ) {
        self.extensionIdentifier = extensionIdentifier
        self.commandIdentifier = commandIdentifier
        self.context = context
        self.options = options
    }
}

public enum GrammarExtensionFindingSeverity: String, CaseIterable, Codable, Sendable {
    case information
    case warning
    case error
}

public struct GrammarExtensionFinding: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let severity: GrammarExtensionFindingSeverity
    public let title: String
    public let message: String
    public let range: SourceRange?

    public init(
        id: String,
        severity: GrammarExtensionFindingSeverity,
        title: String,
        message: String,
        range: SourceRange? = nil
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.message = message
        self.range = range
    }
}

/// Portable output from an extension command. Files are returned to the host;
/// the extension boundary never writes them or mutates a project implicitly.
public struct GrammarExtensionResult: Hashable, Codable, Sendable {
    public let extensionIdentifier: String
    public let commandIdentifier: String
    public let summary: String
    public let findings: [GrammarExtensionFinding]
    public let files: [GrammarGeneratedFile]
    public let properties: [String: String]

    public init(
        extensionIdentifier: String,
        commandIdentifier: String,
        summary: String,
        findings: [GrammarExtensionFinding] = [],
        files: [GrammarGeneratedFile] = [],
        properties: [String: String] = [:]
    ) {
        self.extensionIdentifier = extensionIdentifier
        self.commandIdentifier = commandIdentifier
        self.summary = summary
        self.findings = findings
        self.files = files
        self.properties = properties
    }
}

/// Trusted, in-process extensions implement one asynchronous command entry
/// point. Process isolation and remote execution remain transport concerns.
public protocol GrammarWorkbenchExtension: Sendable {
    var manifest: GrammarWorkbenchExtensionManifest { get }
    func run(_ request: GrammarExtensionRequest) async throws -> GrammarExtensionResult
}

public struct GrammarExtensionHostLimits: Hashable, Codable, Sendable {
    public var maximumCommandsPerExtension: Int
    public var maximumFindingsPerResult: Int
    public var maximumFilesPerResult: Int
    public var maximumOutputBytesPerResult: Int

    public init(
        maximumCommandsPerExtension: Int = 128,
        maximumFindingsPerResult: Int = 10_000,
        maximumFilesPerResult: Int = 64,
        maximumOutputBytesPerResult: Int = 16 * 1_024 * 1_024
    ) {
        self.maximumCommandsPerExtension = max(1, maximumCommandsPerExtension)
        self.maximumFindingsPerResult = max(1, maximumFindingsPerResult)
        self.maximumFilesPerResult = max(1, maximumFilesPerResult)
        self.maximumOutputBytesPerResult = max(1, maximumOutputBytesPerResult)
    }
}

public struct GrammarExtensionRegistrySnapshot: Hashable, Codable, Sendable {
    public let schemaVersion: Int
    public let hostAPIVersion: Int
    public let extensions: [GrammarWorkbenchExtensionManifest]

    public init(extensions: [GrammarWorkbenchExtensionManifest]) {
        schemaVersion = GrammarWorkbenchExtensionContract.schemaVersion
        hostAPIVersion = GrammarWorkbenchAPIVersion.current
        self.extensions = extensions.sorted { $0.id < $1.id }
    }
}

public enum GrammarExtensionRegistryError: Error, LocalizedError, Sendable {
    case unsupportedSchema(Int)
    case incompatibleHostAPI(required: Int, available: Int)
    case invalidIdentifier(String)
    case invalidVersion(String)
    case emptyMetadata(String)
    case emptyCommands(String)
    case duplicateExtension(String)
    case duplicateCommand(String)
    case duplicateOption(String)
    case invalidDefault(name: String, value: String)
    case unknownExtension(String)
    case unknownCommand(String)
    case unknownOption(String)
    case invalidOption(name: String, value: String)
    case mismatchedResult
    case invalidFilename(String)
    case duplicateFilename(String)
    case duplicateFinding(String)
    case limitExceeded(resource: String, limit: Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            "Extension schema \(version) is not supported."
        case .incompatibleHostAPI(let required, let available):
            "Extension requires host API \(required), but this host provides \(available)."
        case .invalidIdentifier(let value): "Invalid extension identifier ‘\(value)’."
        case .invalidVersion(let value): "Invalid extension semantic version ‘\(value)’."
        case .emptyMetadata(let field): "Extension metadata field ‘\(field)’ must not be empty."
        case .emptyCommands(let id): "Extension ‘\(id)’ does not declare any commands."
        case .duplicateExtension(let id): "Extension ‘\(id)’ is already registered."
        case .duplicateCommand(let id): "Extension command ‘\(id)’ is declared more than once."
        case .duplicateOption(let name): "Extension option ‘\(name)’ is declared more than once."
        case .invalidDefault(let name, let value):
            "Default value ‘\(value)’ is not allowed for extension option ‘\(name)’."
        case .unknownExtension(let id): "No extension named ‘\(id)’ is registered."
        case .unknownCommand(let id): "No extension command named ‘\(id)’ is registered."
        case .unknownOption(let name): "Unknown extension option ‘\(name)’."
        case .invalidOption(let name, let value):
            "Invalid value ‘\(value)’ for extension option ‘\(name)’."
        case .mismatchedResult: "Extension result identity does not match its request."
        case .invalidFilename(let name): "Extension output filename ‘\(name)’ is not a safe leaf filename."
        case .duplicateFilename(let name): "Extension produced output filename ‘\(name)’ more than once."
        case .duplicateFinding(let id): "Extension produced finding identity ‘\(id)’ more than once."
        case .limitExceeded(let resource, let limit):
            "Extension exceeded the \(resource) limit of \(limit)."
        }
    }
}

/// An explicit, concurrency-safe host for trusted package extensions. Each
/// instance owns its registrations; the Workbench has no process-global plugin
/// state and performs no implicit bundle or filesystem discovery.
public actor GrammarWorkbenchExtensionRegistry {
    private var extensions: [String: any GrammarWorkbenchExtension] = [:]
    private let limits: GrammarExtensionHostLimits

    public init(limits: GrammarExtensionHostLimits = .init()) {
        self.limits = limits
    }

    public func register(
        _ extensionValue: any GrammarWorkbenchExtension,
        replacingExisting: Bool = false
    ) throws {
        let manifest = extensionValue.manifest
        try validate(manifest)
        if extensions[manifest.id] != nil, !replacingExisting {
            throw GrammarExtensionRegistryError.duplicateExtension(manifest.id)
        }
        extensions[manifest.id] = extensionValue
    }

    @discardableResult
    public func unregister(identifier: String) -> Bool {
        extensions.removeValue(forKey: identifier) != nil
    }

    public func snapshot() -> GrammarExtensionRegistrySnapshot {
        .init(extensions: extensions.values.map(\.manifest))
    }

    public func run(
        extensionIdentifier: String,
        commandIdentifier: String,
        compilation: GrammarCompilation,
        options: GrammarExtensionOptions = .init()
    ) async throws -> GrammarExtensionResult {
        guard let extensionValue = extensions[extensionIdentifier] else {
            throw GrammarExtensionRegistryError.unknownExtension(extensionIdentifier)
        }
        guard let command = extensionValue.manifest.commands.first(where: { $0.id == commandIdentifier }) else {
            throw GrammarExtensionRegistryError.unknownCommand(commandIdentifier)
        }
        let resolvedOptions = try resolve(options, for: command)
        let request = GrammarExtensionRequest(
            extensionIdentifier: extensionIdentifier,
            commandIdentifier: commandIdentifier,
            context: .init(compilation: compilation),
            options: resolvedOptions
        )
        let result = try await extensionValue.run(request)
        try validate(result, request: request)
        return result
    }

    private func validate(_ manifest: GrammarWorkbenchExtensionManifest) throws {
        guard manifest.schemaVersion == GrammarWorkbenchExtensionContract.schemaVersion else {
            throw GrammarExtensionRegistryError.unsupportedSchema(manifest.schemaVersion)
        }
        guard manifest.minimumHostAPIVersion <= GrammarWorkbenchAPIVersion.current else {
            throw GrammarExtensionRegistryError.incompatibleHostAPI(
                required: manifest.minimumHostAPIVersion,
                available: GrammarWorkbenchAPIVersion.current
            )
        }
        guard extensionIdentifierIsValid(manifest.id, requiresNamespace: true) else {
            throw GrammarExtensionRegistryError.invalidIdentifier(manifest.id)
        }
        guard semanticVersionIsValid(manifest.version) else {
            throw GrammarExtensionRegistryError.invalidVersion(manifest.version)
        }
        for (field, value) in [("displayName", manifest.displayName), ("summary", manifest.summary)]
        where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw GrammarExtensionRegistryError.emptyMetadata(field)
        }
        guard !manifest.commands.isEmpty else {
            throw GrammarExtensionRegistryError.emptyCommands(manifest.id)
        }
        guard manifest.commands.count <= limits.maximumCommandsPerExtension else {
            throw GrammarExtensionRegistryError.limitExceeded(
                resource: "command count", limit: limits.maximumCommandsPerExtension
            )
        }
        var commandIDs: Set<String> = []
        for command in manifest.commands {
            guard extensionIdentifierIsValid(command.id, requiresNamespace: false) else {
                throw GrammarExtensionRegistryError.invalidIdentifier(command.id)
            }
            guard commandIDs.insert(command.id).inserted else {
                throw GrammarExtensionRegistryError.duplicateCommand(command.id)
            }
            guard !command.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw GrammarExtensionRegistryError.emptyMetadata("command.displayName")
            }
            guard !command.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw GrammarExtensionRegistryError.emptyMetadata("command.summary")
            }
            var optionNames: Set<String> = []
            for option in command.options {
                guard extensionIdentifierIsValid(option.name, requiresNamespace: false) else {
                    throw GrammarExtensionRegistryError.invalidIdentifier(option.name)
                }
                guard optionNames.insert(option.name).inserted else {
                    throw GrammarExtensionRegistryError.duplicateOption(option.name)
                }
                guard !option.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw GrammarExtensionRegistryError.emptyMetadata("option.summary")
                }
                if let value = option.defaultValue,
                   !option.allowedValues.isEmpty,
                   !option.allowedValues.contains(value) {
                    throw GrammarExtensionRegistryError.invalidDefault(name: option.name, value: value)
                }
            }
        }
    }

    private func resolve(
        _ options: GrammarExtensionOptions,
        for command: GrammarExtensionCommandDescriptor
    ) throws -> GrammarExtensionOptions {
        let declarations = Dictionary(
            command.options.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first }
        )
        var values = Dictionary(uniqueKeysWithValues: command.options.compactMap { option in
            option.defaultValue.map { (option.name, $0) }
        })
        for (name, value) in options.values {
            guard let declaration = declarations[name] else {
                throw GrammarExtensionRegistryError.unknownOption(name)
            }
            if !declaration.allowedValues.isEmpty,
               !declaration.allowedValues.contains(value) {
                throw GrammarExtensionRegistryError.invalidOption(name: name, value: value)
            }
            values[name] = value
        }
        return .init(values)
    }

    private func validate(
        _ result: GrammarExtensionResult,
        request: GrammarExtensionRequest
    ) throws {
        guard result.extensionIdentifier == request.extensionIdentifier,
              result.commandIdentifier == request.commandIdentifier else {
            throw GrammarExtensionRegistryError.mismatchedResult
        }
        guard result.findings.count <= limits.maximumFindingsPerResult else {
            throw GrammarExtensionRegistryError.limitExceeded(
                resource: "finding count", limit: limits.maximumFindingsPerResult
            )
        }
        guard result.files.count <= limits.maximumFilesPerResult else {
            throw GrammarExtensionRegistryError.limitExceeded(
                resource: "file count", limit: limits.maximumFilesPerResult
            )
        }
        var findingIDs: Set<String> = []
        for finding in result.findings where !findingIDs.insert(finding.id).inserted {
            throw GrammarExtensionRegistryError.duplicateFinding(finding.id)
        }
        var filenames: Set<String> = []
        var byteCount = 0
        for file in result.files {
            let filename = file.suggestedFilename
            guard !filename.isEmpty, filename != ".", filename != "..",
                  !filename.contains("/"), !filename.contains("\\"), !filename.contains("\0") else {
                throw GrammarExtensionRegistryError.invalidFilename(filename)
            }
            guard filenames.insert(filename.lowercased()).inserted else {
                throw GrammarExtensionRegistryError.duplicateFilename(filename)
            }
            guard file.contents.count <= limits.maximumOutputBytesPerResult - byteCount else {
                throw GrammarExtensionRegistryError.limitExceeded(
                    resource: "output byte count", limit: limits.maximumOutputBytesPerResult
                )
            }
            byteCount += file.contents.count
        }
    }
}

private func extensionIdentifierIsValid(_ value: String, requiresNamespace: Bool) -> Bool {
    let components = value.split(separator: ".", omittingEmptySubsequences: false)
    guard (!requiresNamespace || components.count >= 2), !components.isEmpty else { return false }
    return components.allSatisfy { component in
        guard let first = component.first, first.isASCII, first.isLetter else { return false }
        return component.allSatisfy { character in
            character.isASCII && (
                character.isLetter || character.isNumber || character == "-"
                    || (!requiresNamespace && character == "_")
            )
        }
    }
}

private func semanticVersionIsValid(_ value: String) -> Bool {
    let buildParts = value.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
    guard !buildParts[0].isEmpty,
          buildParts.count == 1 || semanticVersionIdentifiersAreValid(buildParts[1]) else {
        return false
    }
    let releaseParts = buildParts[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
    guard !releaseParts[0].isEmpty,
          releaseParts.count == 1 || semanticVersionIdentifiersAreValid(releaseParts[1]) else {
        return false
    }
    let numbers = releaseParts[0].split(separator: ".", omittingEmptySubsequences: false)
    return numbers.count == 3 && numbers.allSatisfy { number in
        !number.isEmpty
            && number.allSatisfy { $0.isASCII && $0.isNumber }
            && (number == "0" || number.first != "0")
    }
}

private func semanticVersionIdentifiersAreValid(_ value: Substring) -> Bool {
    value.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { identifier in
        !identifier.isEmpty && identifier.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-")
        }
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
