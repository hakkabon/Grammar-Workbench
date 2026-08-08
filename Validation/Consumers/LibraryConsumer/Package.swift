// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GrammarWorkbenchLibraryConsumer",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(
            name: "LibraryConsumer",
            dependencies: [.product(name: "GrammarWorkbench", package: "Grammar-Workbench")]
        )
    ]
)
