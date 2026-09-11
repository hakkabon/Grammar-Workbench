import Foundation

public enum GrammarWASMExecutionProfile: String, Hashable, Codable, Sendable {
    case wasiCommand
    case browserInterchange
}

public struct GrammarWASMFeasibilityReport: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 2
    public let schemaVersion: Int
    public let maturity: GrammarWorkbenchFeatureMaturity
    public let profiles: [GrammarWASMExecutionProfile]
    public let wasiProduct: String
    public let transport: String
    public let browserDemoUsesPrecomputedArtifact: Bool
    public let nativeGraphLayoutAvailable: Bool
    public let pinnedSwiftVersion: String
    public let pinnedSwiftSDKID: String
    public let wasiTargetTriple: String
    public let browserExecutionModel: String
    public let nativeWASIEquivalenceContract: Bool
    public let constraints: [String]

    public static let current = Self(
        schemaVersion: currentSchemaVersion,
        maturity: .experimental,
        profiles: [.wasiCommand, .browserInterchange],
        wasiProduct: "grammar-workbench-wasi",
        transport: "newline-delimited-json",
        browserDemoUsesPrecomputedArtifact: true,
        nativeGraphLayoutAvailable: false,
        pinnedSwiftVersion: "6.0",
        pinnedSwiftSDKID: "6.0.3-RELEASE-wasm32-unknown-wasi",
        wasiTargetTriple: "wasm32-unknown-wasi",
        browserExecutionModel: "precomputed-lr-artifact",
        nativeWASIEquivalenceContract: true,
        constraints: [
            "The pinned Swift WASM SDK is required to build a release WASI executable.",
            "WASI modules require a WASI runtime and do not run directly in a browser.",
            "The browser demonstration consumes portable parser data and does not compile grammars.",
            "The Swift-Layout binary backend is unavailable in WASM builds."
        ]
    )
}
