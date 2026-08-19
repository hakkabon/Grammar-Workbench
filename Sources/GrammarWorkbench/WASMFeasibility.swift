import Foundation

public enum GrammarWASMExecutionProfile: String, Hashable, Codable, Sendable {
    case wasiCommand
    case browserInterchange
}

public struct GrammarWASMFeasibilityReport: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1
    public let schemaVersion: Int
    public let maturity: GrammarWorkbenchFeatureMaturity
    public let profiles: [GrammarWASMExecutionProfile]
    public let wasiProduct: String
    public let transport: String
    public let browserDemoUsesPrecomputedArtifact: Bool
    public let nativeGraphLayoutAvailable: Bool
    public let constraints: [String]

    public static let current = Self(
        schemaVersion: currentSchemaVersion,
        maturity: .experimental,
        profiles: [.wasiCommand, .browserInterchange],
        wasiProduct: "grammar-workbench-wasi",
        transport: "newline-delimited-json",
        browserDemoUsesPrecomputedArtifact: true,
        nativeGraphLayoutAvailable: false,
        constraints: [
            "A separately installed Swift WASM SDK is required to build the WASI executable.",
            "WASI modules require a WASI runtime and do not run directly in a browser.",
            "The browser demonstration consumes portable parser data and does not compile grammars.",
            "The Swift-Layout binary backend is unavailable in WASM builds."
        ]
    )
}
