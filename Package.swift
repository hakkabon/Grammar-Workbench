// swift-tools-version: 6.0
import PackageDescription

let lspVendoredPath = "LocalDependencies/Sources"

let package = Package(
    name: "GrammarWorkbench",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GrammarWorkbench", targets: ["GrammarWorkbench"]),
        .executable(name: "GrammarWorkbenchApp", targets: ["GrammarWorkbenchApp"]),
        .executable(name: "grammar-workbench", targets: ["GrammarWorkbenchCLI"]),
        .library(name: "GrammarWorkbenchLSP", targets: ["GrammarWorkbenchLSP"]),
        .executable(name: "grammar-workbench-lsp", targets: ["GrammarWorkbenchLSPApp"]),
        .plugin(name: "GrammarWorkbenchPlugin", targets: ["GrammarWorkbenchPlugin"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/hakkabon/Grammar.git",
            revision: "940fdb4f857391e7cdecbb016adabd33db2121c8"
        )
    ],
    targets: [
        .target(
            name: "GrammarWorkbench",
            dependencies: [.product(name: "Grammar", package: "Grammar")],
            resources: [.process("Resources")]
        ),
        .executableTarget(name: "GrammarWorkbenchApp", dependencies: ["GrammarWorkbench"]),
        .executableTarget(name: "GrammarWorkbenchCLI", dependencies: ["GrammarWorkbench"]),
        .plugin(
            name: "GrammarWorkbenchPlugin",
            capability: .buildTool(),
            dependencies: [.target(name: "GrammarWorkbenchCLI")]
        ),
        .testTarget(name: "GrammarWorkbenchTests", dependencies: ["GrammarWorkbench"]),
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
