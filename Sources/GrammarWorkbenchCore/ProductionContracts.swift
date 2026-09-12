import Foundation

public enum GrammarWorkbenchRelease {
    public static let version = "1.0.17"
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
    public static let reproduciblePortabilityAndReleaseConsolidation: GrammarWorkbenchFeatureMaturity = .stable
    public static let browserAndPortableRuntime: GrammarWorkbenchFeatureMaturity = .stable
    public static let grammarRefactoringAndAuthoringProductivity: GrammarWorkbenchFeatureMaturity = .stable
    public static let languageKitEcosystem: GrammarWorkbenchFeatureMaturity = .stable
    public static let scaleAndInteroperability: GrammarWorkbenchFeatureMaturity = .stable
    public static let collaborativeOrHostedWorkbench: GrammarWorkbenchFeatureMaturity = .stable
    public static let collaborativeExploration: GrammarWorkbenchFeatureMaturity = .stable
    public static let languageDocumentationPipeline: GrammarWorkbenchFeatureMaturity = .stable
    public static let hostedLanguageKitEcosystem: GrammarWorkbenchFeatureMaturity = .stable
    public static let grammarREPLExperimentExplorer: GrammarWorkbenchFeatureMaturity = .stable
    public static let compilerSemanticConvergence: GrammarWorkbenchFeatureMaturity = .stable
    public static let largeIPadAdaptiveWorkbench: GrammarWorkbenchFeatureMaturity = .experimental
}
