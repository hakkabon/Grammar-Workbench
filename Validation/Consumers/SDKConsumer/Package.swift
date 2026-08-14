// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GrammarWorkbenchSDKConsumer",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(
            name: "SDKConsumer",
            dependencies: [.product(name: "GrammarWorkbenchSDK", package: "Grammar-Workbench")]
        )
    ]
)
