// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LSPConsumer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "GrammarWorkbench", path: "../../..")
    ],
    targets: [
        .executableTarget(
            name: "LSPConsumer",
            dependencies: [
                .product(name: "GrammarWorkbenchLSP", package: "GrammarWorkbench")
            ]
        )
    ]
)
