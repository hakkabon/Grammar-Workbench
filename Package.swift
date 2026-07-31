// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GrammarWorkbench",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GrammarWorkbench", targets: ["GrammarWorkbench"]),
        .executable(name: "GrammarWorkbenchApp", targets: ["GrammarWorkbenchApp"]),
        .executable(name: "grammar-workbench", targets: ["GrammarWorkbenchCLI"])
    ],
    targets: [
<<<<<<< HEAD
        .target(name: "GrammarWorkbench"),
        .executableTarget(
            name: "GrammarWorkbenchApp",
            dependencies: ["GrammarWorkbench"],
            path: "Sources/App"
        ),
=======
        .target(name: "GrammarWorkbench", resources: [.process("Resources")]),
        .executableTarget(name: "GrammarWorkbenchApp", dependencies: ["GrammarWorkbench"]),
        .executableTarget(name: "GrammarWorkbenchCLI", dependencies: ["GrammarWorkbench"]),
>>>>>>> dev-branch
        .testTarget(name: "GrammarWorkbenchTests", dependencies: ["GrammarWorkbench"])
    ]
)
