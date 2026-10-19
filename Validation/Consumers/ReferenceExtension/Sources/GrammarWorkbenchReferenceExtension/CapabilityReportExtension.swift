import Foundation
import GrammarWorkbenchCore

/// A deliberately small external extension that demonstrates the supported
/// package-author boundary without importing Workbench implementation targets.
public struct CapabilityReportExtension: GrammarWorkbenchExtension {
    public static let identifier = "org.grammar-workbench.reference.capability-report"

    public let manifest = GrammarWorkbenchExtensionManifest(
        id: Self.identifier,
        displayName: "Grammar capability report",
        version: "1.0.0",
        summary: "Exports a deterministic, engine-neutral grammar capability report.",
        commands: [
            .init(
                id: "capability-report",
                displayName: "Capability report",
                summary: "Reports grammar shape and analysis availability as portable JSON.",
                kind: .export,
                options: [
                    .init(
                        name: "detail",
                        summary: "Controls whether symbol lists are included.",
                        defaultValue: "summary",
                        allowedValues: ["summary", "full"]
                    )
                ]
            )
        ]
    )

    public init() {}

    public func run(_ request: GrammarExtensionRequest) async throws -> GrammarExtensionResult {
        guard let grammar = request.context.grammar else {
            return .init(
                extensionIdentifier: request.extensionIdentifier,
                commandIdentifier: request.commandIdentifier,
                summary: "No compiled grammar is available.",
                findings: [
                    .init(
                        id: "compilation-required",
                        severity: .error,
                        title: "Compilation required",
                        message: "Compile a valid grammar before requesting a capability report."
                    )
                ]
            )
        }

        let full = request.options["detail"] == "full"
        let report = Report(
            schemaVersion: 1,
            hostAPIVersion: request.context.hostAPIVersion,
            startSymbol: grammar.startSymbol,
            terminalCount: grammar.terminals.count,
            nonterminalCount: grammar.nonterminals.count,
            productionCount: grammar.productions.count,
            analysisAvailable: request.context.analysis != nil,
            terminals: full ? grammar.terminals.sorted() : nil,
            nonterminals: full ? grammar.nonterminals.sorted() : nil
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        return .init(
            extensionIdentifier: request.extensionIdentifier,
            commandIdentifier: request.commandIdentifier,
            summary: "Reported \(grammar.productions.count) productions for \(grammar.startSymbol).",
            files: [
                .init(
                    suggestedFilename: "grammar-capabilities.json",
                    mediaType: "application/json",
                    contents: data
                )
            ],
            properties: [
                "analysisAvailable": String(request.context.analysis != nil),
                "detail": full ? "full" : "summary"
            ]
        )
    }

    private struct Report: Codable {
        let schemaVersion: Int
        let hostAPIVersion: Int
        let startSymbol: String
        let terminalCount: Int
        let nonterminalCount: Int
        let productionCount: Int
        let analysisAvailable: Bool
        let terminals: [String]?
        let nonterminals: [String]?
    }
}
