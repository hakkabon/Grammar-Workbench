// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GrammarWorkbench",
    platforms: [.macOS(.v14)],
    products: [
<<<<<<< HEAD
        .executable(name: "grammar-workbench", targets: ["grammar-workbench"]),
        .library(name: "GrammarWorkbench", targets: ["GrammarWorkbench"]),
    ],
    targets: [
        .target(
            name: "GrammarWorkbench",
            dependencies: []
        ),
        .executableTarget(
            name: "grammar-workbench",
            dependencies: ["GrammarWorkbench"],
            path: "Sources/App"),
=======
        .library(name: "GrammarWorkbench", targets: ["GrammarWorkbench"]),
        .executable(name: "GrammarWorkbenchApp", targets: ["GrammarWorkbenchApp"])
    ],
    targets: [
        .target(name: "GrammarWorkbench"),
        .executableTarget(name: "GrammarWorkbenchApp", dependencies: ["GrammarWorkbench"]),
>>>>>>> dev-branch
        .testTarget(name: "GrammarWorkbenchTests", dependencies: ["GrammarWorkbench"])
    ]
)
