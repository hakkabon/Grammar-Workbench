// swift-tools-version: 6.0
import PackageDescription

let lspVendoredPath = "LocalDependencies/Sources"

#if os(macOS)
let nativeAppProducts: [Product] = [
    .executable(name: "GrammarWorkbenchApp", targets: ["GrammarWorkbenchApp"])
]
let nativeAppTargets: [Target] = [
    .executableTarget(name: "GrammarWorkbenchApp", dependencies: ["GrammarWorkbench"])
]
#else
let nativeAppProducts: [Product] = []
let nativeAppTargets: [Target] = []
#endif

let package = Package(
    name: "GrammarWorkbench",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "GrammarWorkbenchCore", targets: ["GrammarWorkbenchCore"]),
        .library(name: "GrammarWorkbench", targets: ["GrammarWorkbench"]),
        .library(name: "GrammarWorkbenchSDK", targets: ["GrammarWorkbenchSDK"]),
        .executable(name: "grammar-workbench", targets: ["GrammarWorkbenchCLI"]),
        .executable(name: "grammar-workbench-service", targets: ["GrammarWorkbenchServiceHost"]),
        .executable(name: "grammar-workbench-wasi", targets: ["GrammarWorkbenchWASIDemo"]),
        .library(name: "GrammarWorkbenchLSP", targets: ["GrammarWorkbenchLSP"]),
        .executable(name: "grammar-workbench-lsp", targets: ["GrammarWorkbenchLSPApp"]),
        .plugin(name: "GrammarWorkbenchPlugin", targets: ["GrammarWorkbenchPlugin"])
    ] + nativeAppProducts,
    dependencies: [
        .package(
             url: "https://github.com/hakkabon/Swift-Layout.git",
             .upToNextMinor(from: "0.0.3")
        ),
        .package(
            url: "https://github.com/hakkabon/Grammar.git",
            .upToNextMinor(from: "0.3.0")
        ),
        .package(
            url: "https://github.com/hakkabon/LR-Parsing.git",
            .upToNextMinor(from: "0.2.0")
        ),
        .package(
            url: "https://github.com/hakkabon/Grammar-DiagramKit.git",
            .upToNextMinor(from: "0.1.0")
        )
    ],
    targets: [
        .target(
            name: "GrammarWorkbenchCore",
            dependencies: [
                .product(name: "Grammar", package: "Grammar"),
                .product(name: "LR-Parsing", package: "LR-Parsing"),
                .product(name: "GrammarDiagramKit", package: "Grammar-DiagramKit"),
                .product(
                    name: "SwiftLayout", package: "Swift-Layout",
                    condition: .when(platforms: [.macOS])
                )
            ],
            resources: [.process("Resources")]
        ),
        .target(
            name: "GrammarWorkbench",
            dependencies: [
                "GrammarWorkbenchCore",
                .product(name: "GrammarDiagramKit", package: "Grammar-DiagramKit")
            ]
        ),
        .target(name: "GrammarWorkbenchSDK", dependencies: ["GrammarWorkbenchCore"]),
        .executableTarget(
            name: "GrammarWorkbenchCLI",
            dependencies: ["GrammarWorkbenchCore", "GrammarWorkbenchSDK"]
        ),
        .executableTarget(
            name: "GrammarWorkbenchServiceHost",
            dependencies: ["GrammarWorkbenchSDK", "GrammarWorkbenchCore"]
        ),
        .executableTarget(
            name: "GrammarWorkbenchWASIDemo",
            dependencies: ["GrammarWorkbenchSDK"]
        ),
        .plugin(
            name: "GrammarWorkbenchPlugin",
            capability: .buildTool(),
            dependencies: [.target(name: "GrammarWorkbenchCLI")]
        ),
        .testTarget(
            name: "GrammarWorkbenchTests",
            dependencies: ["GrammarWorkbench", "GrammarWorkbenchCore"]
        ),
        .testTarget(
            name: "GrammarWorkbenchSDKTests",
            dependencies: ["GrammarWorkbenchSDK", "GrammarWorkbenchCore"]
        ),
        .testTarget(name: "GrammarWorkbenchCoreTests", dependencies: ["GrammarWorkbenchCore"]),
        .target(
            name: "LanguageServerProtocol", dependencies: ["SKLogging"],
            path: "\(lspVendoredPath)/LanguageServerProtocol"
        ),
        .target(
            name: "LanguageServerProtocolTransport",
            dependencies: ["LanguageServerProtocol", "SKLogging"],
            path: "\(lspVendoredPath)/LanguageServerProtocolTransport"
        ),
        .target(name: "SKLogging", path: "\(lspVendoredPath)/SKLogging"),
        .target(
            name: "GrammarWorkbenchLSP",
            dependencies: [
                "GrammarWorkbenchCore", "LanguageServerProtocol", "LanguageServerProtocolTransport"
            ]
        ),
        .executableTarget(name: "GrammarWorkbenchLSPApp", dependencies: ["GrammarWorkbenchLSP"]),
        .testTarget(
            name: "GrammarWorkbenchLSPTests",
            dependencies: [
                "GrammarWorkbenchLSP", "GrammarWorkbenchCore",
                "LanguageServerProtocol", "LanguageServerProtocolTransport"
            ]
        )
    ] + nativeAppTargets
)
