import Foundation

public enum GrammarRuntimeOperatingSystem: String, Hashable, Codable, Sendable {
    case macOS, linux, wasi, windows, unknown
}

public enum GrammarRuntimeArchitecture: String, Hashable, Codable, Sendable {
    case arm64, x86_64, wasm32, unknown
}

/// Machine-readable deployment information for launchers, editor clients, and
/// support diagnostics. Values are selected at compile time and require no
/// platform-specific process invocation.
public struct GrammarRuntimePlatformReport: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1
    public let schemaVersion: Int
    public let operatingSystem: GrammarRuntimeOperatingSystem
    public let architecture: GrammarRuntimeArchitecture
    public let releaseVersion: String
    public let apiVersion: Int
    public let graphLayoutAvailability: GrammarGraphLayoutAvailability
    public let deliveredProducts: [String]

    public static var current: Self {
        .init(
            schemaVersion: currentSchemaVersion,
            operatingSystem: operatingSystem,
            architecture: architecture,
            releaseVersion: GrammarWorkbenchRelease.version,
            apiVersion: GrammarWorkbenchAPIVersion.current,
            graphLayoutAvailability: GrammarGraphLayoutEngine.availability,
            deliveredProducts: [
                "GrammarWorkbenchCore", "GrammarWorkbenchSDK", "grammar-workbench",
                "grammar-workbench-lsp", "grammar-workbench-service"
            ]
        )
    }

    private static var operatingSystem: GrammarRuntimeOperatingSystem {
#if os(WASI)
        .wasi
#elseif os(macOS)
        .macOS
#elseif os(Linux)
        .linux
#elseif os(Windows)
        .windows
#else
        .unknown
#endif
    }

    private static var architecture: GrammarRuntimeArchitecture {
#if arch(wasm32)
        .wasm32
#elseif arch(arm64)
        .arm64
#elseif arch(x86_64)
        .x86_64
#else
        .unknown
#endif
    }
}
