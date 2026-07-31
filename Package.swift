// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GrammarWorkbench",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GrammarWorkbench", targets: ["GrammarWorkbench"]),
        .executable(name: "GrammarWorkbenchApp", targets: ["GrammarWorkbenchApp"])
    ],
    targets: [
        .target(name: "GrammarWorkbench"),
        .executableTarget(
            name: "GrammarWorkbenchApp",
            dependencies: ["GrammarWorkbench"],
            path: "Sources/App"
        ),
        .testTarget(name: "GrammarWorkbenchTests", dependencies: ["GrammarWorkbench"])
    ]
)
