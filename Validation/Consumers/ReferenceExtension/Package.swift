// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GrammarWorkbenchReferenceExtension",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GrammarWorkbenchReferenceExtension", targets: ["GrammarWorkbenchReferenceExtension"]),
        .executable(name: "ReferenceExtensionConsumer", targets: ["ReferenceExtensionConsumer"])
    ],
    dependencies: [.package(path: "../../..")],
    targets: [
        .target(
            name: "GrammarWorkbenchReferenceExtension",
            dependencies: [.product(name: "GrammarWorkbenchCore", package: "Grammar-Workbench")]
        ),
        .executableTarget(
            name: "ReferenceExtensionConsumer",
            dependencies: [
                "GrammarWorkbenchReferenceExtension",
                .product(name: "GrammarWorkbenchCore", package: "Grammar-Workbench")
            ]
        )
    ]
)
