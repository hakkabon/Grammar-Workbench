// swift-tools-version: 6.0
import PackageDescription

let lspVendoredPath = "LocalDependencies/Sources"

let package = Package(
    name: "GrammarWorkbench",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "GrammarWorkbenchCore", targets: ["GrammarWorkbenchCore"]),
        .library(name: "GrammarWorkbench", targets: ["GrammarWorkbench"]),
        .library(name: "GrammarWorkbenchSDK", targets: ["GrammarWorkbenchSDK"]),
        .executable(name: "GrammarWorkbenchApp", targets: ["GrammarWorkbenchApp"]),
        .executable(name: "grammar-workbench", targets: ["GrammarWorkbenchCLI"]),
        .executable(name: "grammar-workbench-service", targets: ["GrammarWorkbenchServiceHost"]),
        .executable(name: "grammar-workbench-wasi", targets: ["GrammarWorkbenchWASIDemo"]),
        .library(name: "GrammarWorkbenchLSP", targets: ["GrammarWorkbenchLSP"]),
        .executable(name: "grammar-workbench-lsp", targets: ["GrammarWorkbenchLSPApp"]),
        .plugin(name: "GrammarWorkbenchPlugin", targets: ["GrammarWorkbenchPlugin"])
    ],
    dependencies: [
        .package(
             url: "https://github.com/hakkabon/Swift-Layout.git",
             revision: "1c282a3aafb03cb019a9966a42cfa568365f90a1"
        ),
        .package(
            url: "https://github.com/hakkabon/Grammar.git",
            revision: "b965098a7a6b85be53f0b21dba5db2d13e7132af"
        ),
        .package(
            url: "https://github.com/hakkabon/Grammar-DiagramKit.git",
            revision: "bf7d3738e8593899ec53dd823370e853e5b66d2b"
        )
    ],
    targets: [
        .target(
            name: "GrammarWorkbench",
            dependencies: [
                .product(name: "Grammar", package: "Grammar"),
                .product(name: "GrammarDiagramKit", package: "Grammar-DiagramKit"),
                .product(
                    name: "SwiftLayout", package: "Swift-Layout",
                    condition: .when(platforms: [.macOS])
                )
            ],
            resources: [.process("Resources")]
        ),
        .target(name: "GrammarWorkbenchCore", dependencies: ["GrammarWorkbench"]),
        .target(name: "GrammarWorkbenchSDK", dependencies: ["GrammarWorkbench"]),
        .executableTarget(name: "GrammarWorkbenchApp", dependencies: ["GrammarWorkbench"]),
        .executableTarget(
            name: "GrammarWorkbenchCLI",
            dependencies: ["GrammarWorkbench", "GrammarWorkbenchSDK"]
        ),
        .executableTarget(
            name: "GrammarWorkbenchServiceHost",
            dependencies: ["GrammarWorkbenchSDK", "GrammarWorkbench"]
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
        .testTarget(name: "GrammarWorkbenchTests", dependencies: ["GrammarWorkbench"]),
        .testTarget(
            name: "GrammarWorkbenchSDKTests",
            dependencies: ["GrammarWorkbenchSDK", "GrammarWorkbench"]
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
                "GrammarWorkbench", "LanguageServerProtocol", "LanguageServerProtocolTransport"
            ]
        ),
        .executableTarget(name: "GrammarWorkbenchLSPApp", dependencies: ["GrammarWorkbenchLSP"]),
        .testTarget(
            name: "GrammarWorkbenchLSPTests",
            dependencies: [
                "GrammarWorkbenchLSP", "LanguageServerProtocol", "LanguageServerProtocolTransport"
            ]
        )
    ]
)
