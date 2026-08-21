import Foundation
import GrammarWorkbench
import Testing

private func ecosystemPackage(
    _ identifier: String,
    _ version: String,
    dependencies: [GrammarLanguageKitDependency] = []
) throws -> GrammarLanguageKitPackageManifest {
    let parsedVersion = try GrammarLanguageKitVersion(version)
    let suffix = identifier.split(separator: ".").last ?? "kit"
    let manifest = GrammarSemanticLanguageKitManifest(
        identifier: identifier,
        name: "\(suffix) language",
        version: version,
        fileExtensions: [String(suffix)],
        grammar: .init(source: "%token ID /[A-Za-z]+/\n%skip /\\s+/\n%start Document\nDocument : ID ;"),
        semantics: .init(rules: []),
        tests: [.init(name: "identifier", input: "example", expectation: .accept)]
    )
    return .init(
        identifier: identifier, version: parsedVersion,
        languageKit: manifest, dependencies: dependencies
    )
}

private func compatible(_ identifier: String, _ version: String) throws -> GrammarLanguageKitDependency {
    .init(
        identifier: identifier,
        requirement: .compatible(with: try GrammarLanguageKitVersion(version))
    )
}

@Test func languageKitVersionsAndRequirementsAreDeterministic() throws {
    let prerelease = try GrammarLanguageKitVersion("1.2.3-beta")
    let release = try GrammarLanguageKitVersion("1.2.3")
    let next = try GrammarLanguageKitVersion("1.3.0")
    #expect(prerelease < release)
    #expect(GrammarLanguageKitVersionRequirement.compatible(with: release).contains(next))
    #expect(!GrammarLanguageKitVersionRequirement.compatible(with: release).contains(try .init("2.0.0")))
    #expect(throws: GrammarLanguageKitEcosystemError.self) { try GrammarLanguageKitVersion("1.2") }
}

@Test func languageKitPackageAndCatalogRoundTrip() throws {
    let package = try ecosystemPackage("org.example.core", "1.0.0")
    let decoded = try GrammarLanguageKitPackageCodec.decode(
        GrammarLanguageKitPackageCodec.encode(package)
    )
    #expect(decoded.manifest == package)
    #expect(decoded.languageKit.isConformant)

    let catalog = GrammarLanguageKitCatalog(packages: [package])
    #expect(try GrammarLanguageKitCatalogCodec.decode(
        GrammarLanguageKitCatalogCodec.encode(catalog)
    ) == catalog)
}

@Test func languageKitResolverSelectsNewestCompatibleTransitiveClosure() async throws {
    let registry = GrammarLanguageKitPackageRegistry()
    try await registry.add(ecosystemPackage("org.example.core", "1.0.0"))
    try await registry.add(ecosystemPackage("org.example.core", "1.2.0"))
    try await registry.add(ecosystemPackage("org.example.core", "2.0.0"))
    try await registry.add(ecosystemPackage(
        "org.example.app", "1.0.0",
        dependencies: [try compatible("org.example.core", "1.0.0")]
    ))

    let resolution = try await registry.resolve(roots: [try compatible("org.example.app", "1.0.0")])
    let expectedCoreVersion = try GrammarLanguageKitVersion("1.2.0")
    #expect(resolution.roots == ["org.example.app"])
    #expect(resolution.packages.map(\.identifier) == ["org.example.core", "org.example.app"])
    #expect(resolution.packages.first?.version == expectedCoreVersion)
}

@Test func languageKitResolverReportsMissingPackagesAndCycles() async throws {
    let missing = GrammarLanguageKitPackageRegistry()
    await #expect(throws: GrammarLanguageKitEcosystemError.self) {
        try await missing.resolve(roots: [try compatible("org.example.absent", "1.0.0")])
    }

    let cyclic = GrammarLanguageKitPackageRegistry()
    try await cyclic.add(ecosystemPackage(
        "org.example.a", "1.0.0", dependencies: [try compatible("org.example.b", "1.0.0")]
    ))
    try await cyclic.add(ecosystemPackage(
        "org.example.b", "1.0.0", dependencies: [try compatible("org.example.a", "1.0.0")]
    ))
    await #expect(throws: GrammarLanguageKitEcosystemError.self) {
        try await cyclic.resolve(roots: [try compatible("org.example.a", "1.0.0")])
    }
}

@Test func languageKitTemplateProducesAConformantStarterPackage() throws {
    let package = try GrammarLanguageKitTemplate.make(.init(
        identifier: "org.example.template", name: "Template", fileExtension: "tmpl"
    ))
    let validated = try GrammarLanguageKitPackageCodec.validate(package)
    #expect(validated.languageKit.isConformant)
    #expect(validated.manifest.metadata.isEmpty)
    #expect(validated.manifest.languageKit.metadata["template"] == "phase-32")
}
