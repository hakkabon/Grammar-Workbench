// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GrammarWorkbench",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "grammar-workbench", targets: ["GrammarWorkbenchApp"]),
        .library(name: "GrammarWorkbench", targets: ["GrammarWorkbench"]),
    ],
    targets: [
        .target(
            name: "GrammarWorkbench",
            dependencies: []
        ),
        .executableTarget(
            name: "GrammarWorkbenchApp",
            dependencies: ["GrammarWorkbench"],
            path: "Sources/App"
        ),
        .testTarget(name: "GrammarWorkbenchTests", dependencies: ["GrammarWorkbench"])
    ]
)
