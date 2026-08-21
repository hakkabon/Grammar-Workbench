import Foundation

public struct GrammarLanguageKitVersion: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?

    public init(_ value: String) throws {
        let parts = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count == 3, let major = Int(numbers[0]), let minor = Int(numbers[1]),
              let patch = Int(numbers[2]), major >= 0, minor >= 0, patch >= 0,
              parts.count == 1 || !parts[1].isEmpty else {
            throw GrammarLanguageKitEcosystemError.invalidVersion(value)
        }
        self.major = major; self.minor = minor; self.patch = patch
        prerelease = parts.count == 2 ? String(parts[1]) : nil
    }

    public var description: String {
        "\(major).\(minor).\(patch)" + (prerelease.map { "-\($0)" } ?? "")
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): return false
        case (.some, nil): return true
        case (nil, .some): return false
        case (.some(let left), .some(let right)): return left < right
        }
    }

    public init(from decoder: Decoder) throws { try self.init(decoder.singleValueContainer().decode(String.self)) }
    public func encode(to encoder: Encoder) throws { var value = encoder.singleValueContainer(); try value.encode(description) }
}

public struct GrammarLanguageKitVersionRequirement: Hashable, Codable, Sendable {
    public let minimum: GrammarLanguageKitVersion
    public let maximumExclusive: GrammarLanguageKitVersion?

    public init(minimum: GrammarLanguageKitVersion, maximumExclusive: GrammarLanguageKitVersion? = nil) {
        self.minimum = minimum; self.maximumExclusive = maximumExclusive
    }

    public static func compatible(with version: GrammarLanguageKitVersion) -> Self {
        let maximum = GrammarLanguageKitVersion(
            major: version.major > 0 ? version.major + 1 : 0,
            minor: version.major > 0 ? 0 : version.minor + 1,
            patch: 0
        )
        return .init(minimum: version, maximumExclusive: maximum)
    }

    public func contains(_ version: GrammarLanguageKitVersion) -> Bool {
        version >= minimum && maximumExclusive.map { version < $0 } != false
    }
}

private extension GrammarLanguageKitVersion {
    init(major: Int, minor: Int, patch: Int, prerelease: String? = nil) {
        self.major = major; self.minor = minor; self.patch = patch; self.prerelease = prerelease
    }
}

public struct GrammarLanguageKitDependency: Hashable, Codable, Sendable {
    public let identifier: String
    public let requirement: GrammarLanguageKitVersionRequirement

    public init(identifier: String, requirement: GrammarLanguageKitVersionRequirement) {
        self.identifier = identifier; self.requirement = requirement
    }
}

public struct GrammarLanguageKitPackageManifest: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1
    public static let kindIdentifier = "grammar-workbench-language-kit-package"

    public let schemaVersion: Int
    public let kind: String
    public let apiVersion: Int
    public var identifier: String
    public var version: GrammarLanguageKitVersion
    public var languageKit: GrammarSemanticLanguageKitManifest
    public var dependencies: [GrammarLanguageKitDependency]
    public var metadata: [String: String]

    public init(
        identifier: String, version: GrammarLanguageKitVersion,
        languageKit: GrammarSemanticLanguageKitManifest,
        dependencies: [GrammarLanguageKitDependency] = [], metadata: [String: String] = [:]
    ) {
        schemaVersion = Self.currentSchemaVersion; kind = Self.kindIdentifier
        apiVersion = GrammarWorkbenchAPI.version; self.identifier = identifier
        self.version = version; self.languageKit = languageKit
        self.dependencies = dependencies; self.metadata = metadata
    }
}

public struct GrammarLanguageKitPackage: Sendable {
    public let manifest: GrammarLanguageKitPackageManifest
    public let languageKit: GrammarSemanticLanguageKit
}

public struct GrammarLanguageKitResolutionEntry: Hashable, Codable, Sendable {
    public let identifier: String
    public let version: GrammarLanguageKitVersion
    public let directDependencies: [String]
}

public struct GrammarLanguageKitResolution: Hashable, Codable, Sendable {
    public let roots: [String]
    /// Dependencies precede dependents; ties are ordered by identifier.
    public let packages: [GrammarLanguageKitResolutionEntry]
}

/// A deterministic, self-contained package source suitable for source control,
/// release archives, and offline tooling.
public struct GrammarLanguageKitCatalog: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1
    public static let kindIdentifier = "grammar-workbench-language-kit-catalog"

    public let schemaVersion: Int
    public let kind: String
    public var packages: [GrammarLanguageKitPackageManifest]

    public init(packages: [GrammarLanguageKitPackageManifest]) {
        schemaVersion = Self.currentSchemaVersion
        kind = Self.kindIdentifier
        self.packages = packages
    }
}

public enum GrammarLanguageKitCatalogCodec {
    public static func encode(_ catalog: GrammarLanguageKitCatalog) throws -> Data {
        try validate(catalog)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(catalog)
    }

    public static func decode(_ data: Data) throws -> GrammarLanguageKitCatalog {
        let catalog = try JSONDecoder().decode(GrammarLanguageKitCatalog.self, from: data)
        try validate(catalog)
        return catalog
    }

    public static func validate(_ catalog: GrammarLanguageKitCatalog) throws {
        guard catalog.schemaVersion == GrammarLanguageKitCatalog.currentSchemaVersion else {
            throw GrammarLanguageKitEcosystemError.unsupportedSchema(catalog.schemaVersion)
        }
        guard catalog.kind == GrammarLanguageKitCatalog.kindIdentifier else {
            throw GrammarLanguageKitEcosystemError.invalidKind(catalog.kind)
        }
        var identities: Set<String> = []
        for package in catalog.packages {
            _ = try GrammarLanguageKitPackageCodec.validate(package)
            let identity = "\(package.identifier)@\(package.version)"
            guard identities.insert(identity).inserted else {
                throw GrammarLanguageKitEcosystemError.duplicatePackage(package.identifier, package.version.description)
            }
        }
    }
}

public enum GrammarLanguageKitEcosystemError: Error, LocalizedError, Sendable {
    case unsupportedSchema(Int)
    case unsupportedAPI(Int)
    case invalidKind(String)
    case invalidVersion(String)
    case identityMismatch(package: String, kit: String)
    case versionMismatch(package: String, kit: String)
    case duplicateDependency(String)
    case selfDependency(String)
    case duplicatePackage(String, String)
    case unresolvedDependency(String)
    case incompatibleRequirements(String)
    case dependencyCycle([String])
    case invalidTemplate(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let value): "Unsupported language-kit package schema \(value)."
        case .unsupportedAPI(let value): "Unsupported Grammar Workbench API version \(value)."
        case .invalidKind(let value): "Unexpected language-kit package kind '\(value)'."
        case .invalidVersion(let value): "Language-kit version '\(value)' is not semantic version major.minor.patch."
        case .identityMismatch(let package, let kit): "Package identifier '\(package)' does not match kit identifier '\(kit)'."
        case .versionMismatch(let package, let kit): "Package version '\(package)' does not match kit version '\(kit)'."
        case .duplicateDependency(let value): "Dependency '\(value)' is declared more than once."
        case .selfDependency(let value): "Language-kit package '\(value)' cannot depend on itself."
        case .duplicatePackage(let id, let version): "Language-kit package '\(id)' version '\(version)' is already available."
        case .unresolvedDependency(let value): "No available package satisfies dependency '\(value)'."
        case .incompatibleRequirements(let value): "Language-kit dependency requirements for '\(value)' are incompatible."
        case .dependencyCycle(let values): "Language-kit dependency cycle: \(values.joined(separator: " -> "))."
        case .invalidTemplate(let value): "Cannot create language-kit template: \(value)"
        }
    }
}

public enum GrammarLanguageKitPackageCodec {
    public static func encode(_ package: GrammarLanguageKitPackageManifest) throws -> Data {
        _ = try validate(package)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(package)
    }

    public static func decode(_ data: Data) throws -> GrammarLanguageKitPackage {
        try validate(JSONDecoder().decode(GrammarLanguageKitPackageManifest.self, from: data))
    }

    public static func validate(_ manifest: GrammarLanguageKitPackageManifest) throws -> GrammarLanguageKitPackage {
        guard manifest.schemaVersion == GrammarLanguageKitPackageManifest.currentSchemaVersion else { throw GrammarLanguageKitEcosystemError.unsupportedSchema(manifest.schemaVersion) }
        guard manifest.apiVersion == GrammarWorkbenchAPI.version else { throw GrammarLanguageKitEcosystemError.unsupportedAPI(manifest.apiVersion) }
        guard manifest.kind == GrammarLanguageKitPackageManifest.kindIdentifier else { throw GrammarLanguageKitEcosystemError.invalidKind(manifest.kind) }
        guard manifest.identifier == manifest.languageKit.identifier else { throw GrammarLanguageKitEcosystemError.identityMismatch(package: manifest.identifier, kit: manifest.languageKit.identifier) }
        guard manifest.version.description == manifest.languageKit.version else { throw GrammarLanguageKitEcosystemError.versionMismatch(package: manifest.version.description, kit: manifest.languageKit.version) }
        var dependencies: Set<String> = []
        for dependency in manifest.dependencies {
            guard dependency.identifier != manifest.identifier else { throw GrammarLanguageKitEcosystemError.selfDependency(manifest.identifier) }
            guard dependencies.insert(dependency.identifier).inserted else { throw GrammarLanguageKitEcosystemError.duplicateDependency(dependency.identifier) }
            if let maximum = dependency.requirement.maximumExclusive, maximum <= dependency.requirement.minimum { throw GrammarLanguageKitEcosystemError.incompatibleRequirements(dependency.identifier) }
        }
        return .init(manifest: manifest, languageKit: try GrammarSemanticLanguageKit.compile(manifest.languageKit))
    }
}

public actor GrammarLanguageKitPackageRegistry {
    private var packages: [String: [GrammarLanguageKitVersion: GrammarLanguageKitPackage]] = [:]
    public init() {}

    public func add(_ manifest: GrammarLanguageKitPackageManifest) throws {
        let package = try GrammarLanguageKitPackageCodec.validate(manifest)
        if packages[manifest.identifier]?[manifest.version] != nil { throw GrammarLanguageKitEcosystemError.duplicatePackage(manifest.identifier, manifest.version.description) }
        packages[manifest.identifier, default: [:]][manifest.version] = package
    }

    public func availableVersions(for identifier: String) -> [GrammarLanguageKitVersion] {
        packages[identifier, default: [:]].keys.sorted(by: >)
    }

    public func resolve(roots: [GrammarLanguageKitDependency]) throws -> GrammarLanguageKitResolution {
        let rootIDs = roots.map(\.identifier)
        guard let selected = solve(requirements: roots, selected: [:]) else {
            let missing = roots.first { root in
                packages[root.identifier, default: [:]].keys.allSatisfy { version in
                    !root.requirement.contains(version)
                }
            }
            throw GrammarLanguageKitEcosystemError.unresolvedDependency(missing?.identifier ?? rootIDs.first ?? "unknown")
        }
        let order = try topologicalOrder(selected)
        return .init(roots: rootIDs, packages: order.map { id in
            let package = selected[id]!
            return .init(identifier: id, version: package.manifest.version, directDependencies: package.manifest.dependencies.map(\.identifier).sorted())
        })
    }

    public func add(contentsOf catalog: GrammarLanguageKitCatalog) throws {
        try GrammarLanguageKitCatalogCodec.validate(catalog)
        for package in catalog.packages { try add(package) }
    }

    private func solve(
        requirements: [GrammarLanguageKitDependency],
        selected: [String: GrammarLanguageKitPackage]
    ) -> [String: GrammarLanguageKitPackage]? {
        guard let requirement = requirements.first else { return selected }
        let remaining = Array(requirements.dropFirst())
        if let existing = selected[requirement.identifier] {
            return requirement.requirement.contains(existing.manifest.version)
                ? solve(requirements: remaining, selected: selected) : nil
        }
        let candidates = packages[requirement.identifier, default: [:]].values
            .filter { requirement.requirement.contains($0.manifest.version) }
            .sorted { $0.manifest.version > $1.manifest.version }
        for candidate in candidates {
            var next = selected; next[requirement.identifier] = candidate
            if let result = solve(requirements: candidate.manifest.dependencies + remaining, selected: next) { return result }
        }
        return nil
    }

    private func topologicalOrder(_ selected: [String: GrammarLanguageKitPackage]) throws -> [String] {
        var temporary: Set<String> = [], permanent: Set<String> = [], output: [String] = []
        func visit(_ identifier: String, path: [String]) throws {
            if permanent.contains(identifier) { return }
            if temporary.contains(identifier) { throw GrammarLanguageKitEcosystemError.dependencyCycle(path + [identifier]) }
            temporary.insert(identifier)
            for dependency in selected[identifier]?.manifest.dependencies.map(\.identifier).sorted() ?? [] { try visit(dependency, path: path + [identifier]) }
            temporary.remove(identifier); permanent.insert(identifier); output.append(identifier)
        }
        for identifier in selected.keys.sorted() { try visit(identifier, path: []) }
        return output
    }
}

public struct GrammarLanguageKitTemplateRequest: Hashable, Codable, Sendable {
    public let identifier: String, name: String, version: String, fileExtension: String
    public init(identifier: String, name: String, version: String = "0.1.0", fileExtension: String) {
        self.identifier = identifier; self.name = name; self.version = version; self.fileExtension = fileExtension
    }
}

public enum GrammarLanguageKitTemplate {
    public static func make(_ request: GrammarLanguageKitTemplateRequest) throws -> GrammarLanguageKitPackageManifest {
        let version = try GrammarLanguageKitVersion(request.version)
        let grammar = "%token ID /[A-Za-z_][A-Za-z0-9_]*/\n%skip /\\s+/\n%start Document\nDocument : ID ;"
        let kit = GrammarSemanticLanguageKitManifest(
            identifier: request.identifier, name: request.name, version: version.description,
            fileExtensions: [request.fileExtension], grammar: .init(source: grammar),
            semantics: .init(rules: []), tests: [.init(name: "identifier", input: "example", expectation: .accept)],
            metadata: ["template": "phase-32"]
        )
        do { return try GrammarLanguageKitPackageCodec.validate(.init(identifier: request.identifier, version: version, languageKit: kit)).manifest }
        catch { throw GrammarLanguageKitEcosystemError.invalidTemplate(error.localizedDescription) }
    }
}
