// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GrammarWorkbenchPluginConsumer",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(
            name: "PluginConsumer",
            plugins: [.plugin(name: "GrammarWorkbenchPlugin", package: "Grammar-Workbench")]
        )
    ]
)
