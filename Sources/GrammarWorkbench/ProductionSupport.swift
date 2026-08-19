import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

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
    public static let guidedGrammarEngineering: GrammarWorkbenchFeatureMaturity = .stable
    public static let grammarAnalysisAndTransformation: GrammarWorkbenchFeatureMaturity = .stable
    public static let bootstrapLaboratory: GrammarWorkbenchFeatureMaturity = .stable
    public static let sharedForestsAndScalableGeneralizedParsing: GrammarWorkbenchFeatureMaturity = .stable
    public static let semanticWorkspaceServices: GrammarWorkbenchFeatureMaturity = .stable
    public static let languageToolingSDKAndPortability: GrammarWorkbenchFeatureMaturity = .stable
    public static let integratedLanguageProjectExperience: GrammarWorkbenchFeatureMaturity = .stable
    public static let statefulToolingProtocolAndServiceHost: GrammarWorkbenchFeatureMaturity = .stable
    public static let semanticLanguageKits: GrammarWorkbenchFeatureMaturity = .stable
    public static let graphVisualizationPlatform: GrammarWorkbenchFeatureMaturity = .stable
    public static let crossPlatformCoreSeparation: GrammarWorkbenchFeatureMaturity = .stable
    public static let bootstrapAndInterchangeExpansion: GrammarWorkbenchFeatureMaturity = .stable
    public static let researchValidationProgramme: GrammarWorkbenchFeatureMaturity = .stable
    public static let selectedResearchPreview: GrammarWorkbenchFeatureMaturity = .stable
    public static let sourceProjectsAndExternalEditorWorkflow: GrammarWorkbenchFeatureMaturity = .stable
    public static let graphCorrectnessAndMeasurement: GrammarWorkbenchFeatureMaturity = .stable
    public static let advancedGraphGeometry: GrammarWorkbenchFeatureMaturity = .stable
    public static let interactiveParserVisualization: GrammarWorkbenchFeatureMaturity = .stable
    public static let visualProductConsolidation: GrammarWorkbenchFeatureMaturity = .stable
    public static let linuxDelivery: GrammarWorkbenchFeatureMaturity = .stable
    public static let wasmFeasibilityAndPortableDemonstration: GrammarWorkbenchFeatureMaturity = .experimental
}

#if canImport(SwiftUI)
public struct GrammarWorkbenchSettingsView: View {
    @AppStorage("openLastDocument") private var openLastDocument = true
    @AppStorage("confirmArtifactExport") private var confirmArtifactExport = false
    @AppStorage("visualAppearance") private var visualAppearance = GrammarVisualAppearance.system.rawValue
    @AppStorage("reduceGraphMotion") private var reduceGraphMotion = false
    @AppStorage("showGraphMinimap") private var showGraphMinimap = true
    @AppStorage("showGraphEdgeLabels") private var showGraphEdgeLabels = true

    public init() {}

    public var body: some View {
        Form {
            Toggle("Reopen the last document at launch", isOn: $openLastDocument)
            Toggle("Confirm generated artifact exports", isOn: $confirmArtifactExport)
            Picker("Graph appearance", selection: $visualAppearance) {
                ForEach(GrammarVisualAppearance.allCases, id: \.rawValue) {
                    Text($0.rawValue.capitalized).tag($0.rawValue)
                }
            }
            Toggle("Reduce graph animation", isOn: $reduceGraphMotion)
            Toggle("Show graph minimaps", isOn: $showGraphMinimap)
            Toggle("Show graph edge labels", isOn: $showGraphEdgeLabels)
            LabeledContent("Version", value: GrammarWorkbenchRelease.displayVersion)
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 460)
    }
}
#endif
