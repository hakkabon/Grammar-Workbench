// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GrammarWorkbench",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "GrammarWorkbench", targets: ["GrammarWorkbench"])
    ],
    targets: [
        .executableTarget(name: "GrammarWorkbench"),
        .testTarget(name: "GrammarWorkbenchTests", dependencies: ["GrammarWorkbench"])
    ]
)
