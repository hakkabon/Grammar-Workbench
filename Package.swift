// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GrammarWorkbench",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GrammarWorkbench", targets: ["GrammarWorkbench"]),
        .executable(name: "GrammarWorkbenchApp", targets: ["GrammarWorkbenchApp"]),
        .executable(name: "grammar-workbench", targets: ["GrammarWorkbenchCLI"]),
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
        .testTarget(name: "GrammarWorkbenchTests", dependencies: ["GrammarWorkbench"])
    ]
)
