// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GrammarWorkbenchCoreConsumer",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(
            name: "CoreConsumer",
            dependencies: [.product(name: "GrammarWorkbenchCore", package: "Grammar-Workbench")]
        )
    ]
)
