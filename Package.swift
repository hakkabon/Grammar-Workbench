// swift-tools-version: 6.0
import PackageDescription

let lspVendoredPath = "LocalDependencies/Sources"

let package = Package(
    name: "GrammarWorkbench",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "GrammarWorkbench", targets: ["GrammarWorkbench"]),
        .executable(name: "grammar-workbench-app", targets: ["GrammarWorkbenchApp"]),
        .executable(name: "grammar-workbench", targets: ["GrammarWorkbenchCLI"]),
        .executable(name: "grammar-workbench-lsp", targets: ["GrammarWorkbenchLSP"]),
        .plugin(name: "GrammarWorkbenchPlugin", targets: ["GrammarWorkbenchPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/hakkabon/Grammar.git", branch: "main"),
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

        // Vendored Language Server Protocol framework. See LocalDependencies/README.md
        // for provenance and for how to swap these for the upstream
        // swiftlang/swift-tools-protocols package on a Swift 6.2+ toolchain.
        .target(
            name: "LanguageServerProtocol",
            path: "\(lspVendoredPath)/LanguageServerProtocol"
        ),
<<<<<<< HEAD
//        .target(
//            name: "ToolsProtocolsSwiftExtensions",
//            path: "\(lspVendoredPath)/ToolsProtocolsSwiftExtensions"
//        ),
//        .target(
//            name: "SKLogging",
//            dependencies: ["ToolsProtocolsSwiftExtensions"],
//            path: "\(lspVendoredPath)/SKLogging"
//        ),
        .target(
            name: "LanguageServerProtocolTransport",
            dependencies: ["LanguageServerProtocol"],
=======
        // A local, minimal stand-in for the upstream `SKLogging` module (which
        // requires Swift 6.2 / macOS 15); see LocalDependencies/README.md.
        .target(
            name: "SKLogging",
            path: "\(lspVendoredPath)/SKLogging"
        ),
        .target(
            name: "LanguageServerProtocolTransport",
            dependencies: ["LanguageServerProtocol", "SKLogging"],
>>>>>>> dev-branch
            path: "\(lspVendoredPath)/LanguageServerProtocolTransport"
        ),

        .executableTarget(
            name: "GrammarWorkbenchLSP",
            dependencies: [
                "GrammarWorkbench",
                "LanguageServerProtocol",
                "LanguageServerProtocolTransport",
            ]
        ),
        .testTarget(
            name: "GrammarWorkbenchLSPTests",
            dependencies: [
                "GrammarWorkbenchLSP",
                "LanguageServerProtocol",
                "LanguageServerProtocolTransport",
            ]
        ),
    ]
)
