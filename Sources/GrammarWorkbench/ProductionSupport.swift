import Foundation
import SwiftUI

public enum GrammarWorkbenchRelease {
    public static let version = "1.0.0"
    public static let bundleIdentifier = "com.grammar-workbench.app"

    public static var displayVersion: String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? Self.version
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    public static var gettingStarted: String {
        guard let url = Bundle.module.url(forResource: "GettingStarted", withExtension: "md"),
              let value = try? String(contentsOf: url, encoding: .utf8) else {
            return "Grammar Workbench \(displayVersion)"
        }
        return value
    }
}

public enum GrammarWorkbenchFeatureMaturity: String, Codable, Sendable {
    case stable
    case experimental
}

/// Machine-readable maturity declarations for downstream compatibility gates.
public enum GrammarWorkbenchCapabilities {
    public static let deterministicParsing: GrammarWorkbenchFeatureMaturity = .stable
    public static let semanticOutput: GrammarWorkbenchFeatureMaturity = .stable
    public static let generatorEcosystem: GrammarWorkbenchFeatureMaturity = .stable
    public static let languageServer: GrammarWorkbenchFeatureMaturity = .stable
    public static let generalizedParsing: GrammarWorkbenchFeatureMaturity = .stable
    public static let incrementalLanguageInfrastructure: GrammarWorkbenchFeatureMaturity = .stable
    public static let projectInfrastructure: GrammarWorkbenchFeatureMaturity = .stable
    public static let advancedParsingPlatform: GrammarWorkbenchFeatureMaturity = .stable
}

public struct GrammarWorkbenchSettingsView: View {
    @AppStorage("openLastDocument") private var openLastDocument = true
    @AppStorage("confirmArtifactExport") private var confirmArtifactExport = false

    public init() {}

    public var body: some View {
        Form {
            Toggle("Reopen the last document at launch", isOn: $openLastDocument)
            Toggle("Confirm generated artifact exports", isOn: $confirmArtifactExport)
            LabeledContent("Version", value: GrammarWorkbenchRelease.displayVersion)
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 460)
    }
}
