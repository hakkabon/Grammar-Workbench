import Foundation
import GrammarWorkbench

/// The stable wire schema used by the language-tooling SDK and process adapters.
public enum GrammarToolingSchema {
    public static let current = 1
}

public enum GrammarToolingOperation: String, CaseIterable, Codable, Sendable {
    case capabilities
    case compile
    case parse
    case generalizedParse
    case projectAnalyze
    case semanticWorkspace
    case languageKitValidate
    case languageKitAnalyze
    case graphLayout
    case graphValidate
    case graphMeasure
    case graphDOT
    case graphGeometry
    case portableGrammarImport
    case portableGrammarRender
    case bootstrapBundle
    case researchValidate
    case selectedResearchPreview
    case sessionOpen
    case sessionClose
    case sessionStatus
    case sessionReplaceGrammar
    case documentOpen
    case documentChange
    case documentClose
    case cancel
}

public struct GrammarToolingCapabilities: Hashable, Codable, Sendable {
    public let sdkSchemaVersions: [Int]
    public let grammarWorkbenchAPIVersion: Int
    public let operations: [GrammarToolingOperation]
    public let transports: [String]
    public let features: [String: GrammarWorkbenchFeatureMaturity]

    public static let current = Self(
        sdkSchemaVersions: [GrammarToolingSchema.current],
        grammarWorkbenchAPIVersion: GrammarWorkbenchAPIVersion.current,
        operations: GrammarToolingOperation.allCases,
        transports: ["in-process", "json", "json-lines"],
        features: [
            "deterministicParsing": GrammarWorkbenchCapabilities.deterministicParsing,
            "generalizedParsing": GrammarWorkbenchCapabilities.generalizedParsing,
            "projectInfrastructure": GrammarWorkbenchCapabilities.projectInfrastructure,
            "semanticWorkspaceServices": GrammarWorkbenchCapabilities.semanticWorkspaceServices,
            "semanticLanguageKits": GrammarWorkbenchCapabilities.semanticLanguageKits,
            "graphVisualizationPlatform": GrammarWorkbenchCapabilities.graphVisualizationPlatform,
            "crossPlatformCoreSeparation": GrammarWorkbenchCapabilities.crossPlatformCoreSeparation,
            "bootstrapAndInterchangeExpansion": GrammarWorkbenchCapabilities.bootstrapAndInterchangeExpansion,
            "researchValidationProgramme": GrammarWorkbenchCapabilities.researchValidationProgramme,
            "selectedResearchPreview": GrammarWorkbenchCapabilities.selectedResearchPreview,
            "sourceProjectsAndExternalEditorWorkflow": GrammarWorkbenchCapabilities.sourceProjectsAndExternalEditorWorkflow,
            "graphCorrectnessAndMeasurement": GrammarWorkbenchCapabilities.graphCorrectnessAndMeasurement,
            "advancedGraphGeometry": GrammarWorkbenchCapabilities.advancedGraphGeometry,
            "languageToolingSDKAndPortability": GrammarWorkbenchCapabilities.languageToolingSDKAndPortability,
            "statefulToolingProtocolAndServiceHost": GrammarWorkbenchCapabilities.statefulToolingProtocolAndServiceHost
        ]
    )

    public static let stateless = Self(
        sdkSchemaVersions: [GrammarToolingSchema.current],
        grammarWorkbenchAPIVersion: GrammarWorkbenchAPIVersion.current,
        operations: [
            .capabilities, .compile, .parse, .generalizedParse, .projectAnalyze,
            .semanticWorkspace, .languageKitValidate, .languageKitAnalyze, .graphLayout,
            .graphValidate, .graphMeasure, .graphDOT, .graphGeometry,
            .portableGrammarImport, .portableGrammarRender, .bootstrapBundle, .researchValidate,
            .selectedResearchPreview
        ],
        transports: ["in-process", "json"],
        features: [
            "deterministicParsing": GrammarWorkbenchCapabilities.deterministicParsing,
            "generalizedParsing": GrammarWorkbenchCapabilities.generalizedParsing,
            "projectInfrastructure": GrammarWorkbenchCapabilities.projectInfrastructure,
            "semanticWorkspaceServices": GrammarWorkbenchCapabilities.semanticWorkspaceServices,
            "semanticLanguageKits": GrammarWorkbenchCapabilities.semanticLanguageKits,
            "graphVisualizationPlatform": GrammarWorkbenchCapabilities.graphVisualizationPlatform,
            "crossPlatformCoreSeparation": GrammarWorkbenchCapabilities.crossPlatformCoreSeparation,
            "bootstrapAndInterchangeExpansion": GrammarWorkbenchCapabilities.bootstrapAndInterchangeExpansion,
            "researchValidationProgramme": GrammarWorkbenchCapabilities.researchValidationProgramme,
            "selectedResearchPreview": GrammarWorkbenchCapabilities.selectedResearchPreview,
            "sourceProjectsAndExternalEditorWorkflow": GrammarWorkbenchCapabilities.sourceProjectsAndExternalEditorWorkflow,
            "languageToolingSDKAndPortability": GrammarWorkbenchCapabilities.languageToolingSDKAndPortability,
            "graphCorrectnessAndMeasurement": GrammarWorkbenchCapabilities.graphCorrectnessAndMeasurement,
            "advancedGraphGeometry": GrammarWorkbenchCapabilities.advancedGraphGeometry
        ]
    )
}

/// One transport-neutral tooling request. Unused payloads remain absent, keeping
/// the wire format straightforward for clients that do not use Swift Codable.
public struct GrammarToolingRequest: Hashable, Codable, Sendable {
    public var schemaVersion: Int
    public var requestID: String
    public var apiVersion: Int
    public var operation: GrammarToolingOperation
    public var compilation: GrammarCompilationRequest?
    public var input: String?
    public var parseOptions: GrammarParseOptions?
    public var generalizedOptions: GrammarGeneralizedParseOptions?
    public var project: GrammarProjectManifest?
    public var semanticSchema: GrammarSemanticWorkspaceSchema?
    public var languageKit: GrammarSemanticLanguageKitManifest?
    public var graph: GrammarGraph?
    public var graphLayoutOptions: GrammarGraphLayoutOptions?
    public var graphGeometrySpecification: GrammarGraphGeometrySpecification?
    public var portableSource: String?
    public var portableNotation: GrammarPortableNotation?
    public var portableStartSymbol: String?
    public var portableGrammar: GrammarPortableInterchange?
    public var portableRenderFormat: GrammarPortableRenderFormat?
    public var bootstrapOptions: GrammarBootstrapOptions?
    public var researchProgramme: GrammarResearchProgramme?
    public var researchStudyID: String?
    public var sessionID: String?
    public var documentID: String?
    public var revision: Int?
    public var edits: [GrammarTextEdit]?
    public var targetRequestID: String?

    public init(
        requestID: String = UUID().uuidString,
        operation: GrammarToolingOperation,
        compilation: GrammarCompilationRequest? = nil,
        input: String? = nil,
        parseOptions: GrammarParseOptions? = nil,
        generalizedOptions: GrammarGeneralizedParseOptions? = nil,
        project: GrammarProjectManifest? = nil,
        semanticSchema: GrammarSemanticWorkspaceSchema? = nil,
        languageKit: GrammarSemanticLanguageKitManifest? = nil,
        graph: GrammarGraph? = nil,
        graphLayoutOptions: GrammarGraphLayoutOptions? = nil,
        graphGeometrySpecification: GrammarGraphGeometrySpecification? = nil,
        portableSource: String? = nil,
        portableNotation: GrammarPortableNotation? = nil,
        portableStartSymbol: String? = nil,
        portableGrammar: GrammarPortableInterchange? = nil,
        portableRenderFormat: GrammarPortableRenderFormat? = nil,
        bootstrapOptions: GrammarBootstrapOptions? = nil,
        researchProgramme: GrammarResearchProgramme? = nil,
        researchStudyID: String? = nil,
        sessionID: String? = nil,
        documentID: String? = nil,
        revision: Int? = nil,
        edits: [GrammarTextEdit]? = nil,
        targetRequestID: String? = nil,
        schemaVersion: Int = GrammarToolingSchema.current,
        apiVersion: Int = GrammarWorkbenchAPIVersion.current
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.apiVersion = apiVersion
        self.operation = operation
        self.compilation = compilation
        self.input = input
        self.parseOptions = parseOptions
        self.generalizedOptions = generalizedOptions
        self.project = project
        self.semanticSchema = semanticSchema
        self.languageKit = languageKit
        self.graph = graph
        self.graphLayoutOptions = graphLayoutOptions
        self.graphGeometrySpecification = graphGeometrySpecification
        self.portableSource = portableSource
        self.portableNotation = portableNotation
        self.portableStartSymbol = portableStartSymbol
        self.portableGrammar = portableGrammar
        self.portableRenderFormat = portableRenderFormat
        self.bootstrapOptions = bootstrapOptions
        self.researchProgramme = researchProgramme
        self.researchStudyID = researchStudyID
        self.sessionID = sessionID
        self.documentID = documentID
        self.revision = revision
        self.edits = edits
        self.targetRequestID = targetRequestID
    }
}

public enum GrammarToolingResponseStatus: String, Codable, Sendable {
    case success
    case failure
}

public struct GrammarToolingError: Hashable, Codable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public struct GrammarToolingCompilationResult: Hashable, Codable, Sendable {
    public let succeeded: Bool
    public let diagnostics: [GrammarDiagnostic]
    public let grammar: GrammarSummary?
    public let analysis: GrammarAnalysisSnapshot?
    public let artifact: GrammarArtifactSnapshot?
    public let performance: GrammarConstructionPerformance
}

public struct GrammarToolingProjectDocumentResult: Hashable, Codable, Sendable {
    public let id: String
    public let path: String
    public let revision: Int
    public let parseStatus: GrammarParseStatus
    public let lexicalDiagnosticCount: Int
    public let syntaxDiagnosticCount: Int
    public let semanticEntryCount: Int
}

public struct GrammarToolingProjectResult: Hashable, Codable, Sendable {
    public let name: String
    public let succeeded: Bool
    public let documents: [GrammarToolingProjectDocumentResult]
    public let index: GrammarProjectIndex
    public let passedTests: Int
    public let failedTests: Int
}

public struct GrammarToolingLanguageKitResult: Hashable, Codable, Sendable {
    public let identifier: String
    public let name: String
    public let version: String
    public let fileExtensions: [String]
    public let semanticModel: GrammarSemanticModel
    public let passedTests: Int
    public let failedTests: Int
    public let isConformant: Bool
}

/// A uniform response envelope. Exactly one operation result is normally set.
public struct GrammarToolingResponse: Hashable, Codable, Sendable {
    public let schemaVersion: Int
    public let requestID: String
    public let apiVersion: Int
    public let status: GrammarToolingResponseStatus
    public let error: GrammarToolingError?
    public let capabilities: GrammarToolingCapabilities?
    public let compilation: GrammarToolingCompilationResult?
    public let parse: GrammarParseResult?
    public let generalizedParse: GrammarGeneralizedParseResult?
    public let project: GrammarToolingProjectResult?
    public let semanticWorkspace: GrammarSemanticWorkspaceSnapshot?
    public let languageKit: GrammarToolingLanguageKitResult?
    public let graphLayout: GrammarGraphLayoutSnapshot?
    public let graphCorrectness: GrammarGraphCorrectnessReport?
    public let graphMeasuredLayout: GrammarGraphMeasuredLayout?
    public let renderedGraph: String?
    public let advancedGraphLayout: GrammarGraphAdvancedLayoutSnapshot?
    public let portableGrammar: GrammarPortableInterchange?
    public let renderedGrammar: String?
    public let bootstrapBundle: GrammarBootstrapInterchangeBundle?
    public let researchReport: GrammarResearchReport?
    public let selectedResearchPreview: GrammarSelectedResearchPreview?
    public let session: GrammarToolingSessionSnapshot?
    public let document: GrammarIncrementalAnalysisSnapshot?
    public let events: [GrammarToolingEvent]?

    public init(
        requestID: String,
        status: GrammarToolingResponseStatus = .success,
        error: GrammarToolingError? = nil,
        capabilities: GrammarToolingCapabilities? = nil,
        compilation: GrammarToolingCompilationResult? = nil,
        parse: GrammarParseResult? = nil,
        generalizedParse: GrammarGeneralizedParseResult? = nil,
        project: GrammarToolingProjectResult? = nil,
        semanticWorkspace: GrammarSemanticWorkspaceSnapshot? = nil,
        languageKit: GrammarToolingLanguageKitResult? = nil,
        graphLayout: GrammarGraphLayoutSnapshot? = nil,
        graphCorrectness: GrammarGraphCorrectnessReport? = nil,
        graphMeasuredLayout: GrammarGraphMeasuredLayout? = nil,
        renderedGraph: String? = nil,
        advancedGraphLayout: GrammarGraphAdvancedLayoutSnapshot? = nil,
        portableGrammar: GrammarPortableInterchange? = nil,
        renderedGrammar: String? = nil,
        bootstrapBundle: GrammarBootstrapInterchangeBundle? = nil,
        researchReport: GrammarResearchReport? = nil,
        selectedResearchPreview: GrammarSelectedResearchPreview? = nil,
        session: GrammarToolingSessionSnapshot? = nil,
        document: GrammarIncrementalAnalysisSnapshot? = nil,
        events: [GrammarToolingEvent]? = nil
    ) {
        schemaVersion = GrammarToolingSchema.current
        self.requestID = requestID
        apiVersion = GrammarWorkbenchAPIVersion.current
        self.status = status
        self.error = error
        self.capabilities = capabilities
        self.compilation = compilation
        self.parse = parse
        self.generalizedParse = generalizedParse
        self.project = project
        self.semanticWorkspace = semanticWorkspace
        self.languageKit = languageKit
        self.graphLayout = graphLayout
        self.graphCorrectness = graphCorrectness
        self.graphMeasuredLayout = graphMeasuredLayout
        self.renderedGraph = renderedGraph
        self.advancedGraphLayout = advancedGraphLayout
        self.portableGrammar = portableGrammar
        self.renderedGrammar = renderedGrammar
        self.bootstrapBundle = bootstrapBundle
        self.researchReport = researchReport
        self.selectedResearchPreview = selectedResearchPreview
        self.session = session
        self.document = document
        self.events = events
    }
}

public struct GrammarLanguageToolingService: Sendable {
    public init() {}

    public func handle(_ request: GrammarToolingRequest) async -> GrammarToolingResponse {
        guard request.schemaVersion == GrammarToolingSchema.current else {
            return failure(request, code: "unsupported-schema", message: "Unsupported tooling schema version \(request.schemaVersion).")
        }
        guard request.apiVersion == GrammarWorkbenchAPIVersion.current else {
            return failure(request, code: "unsupported-api", message: "Unsupported Grammar Workbench API version \(request.apiVersion).")
        }
        do {
            switch request.operation {
            case .capabilities:
                return .init(requestID: request.requestID, capabilities: .stateless)
            case .compile:
                let compilation = GrammarWorkbenchAPI.compile(try required(request.compilation, "compilation"))
                return .init(requestID: request.requestID, compilation: snapshot(compilation))
            case .parse:
                let compilation = GrammarWorkbenchAPI.compile(try required(request.compilation, "compilation"))
                return .init(
                    requestID: request.requestID,
                    compilation: snapshot(compilation),
                    parse: compilation.parse(try required(request.input, "input"), options: request.parseOptions ?? .init())
                )
            case .generalizedParse:
                let compilation = GrammarWorkbenchAPI.compile(try required(request.compilation, "compilation"))
                return .init(
                    requestID: request.requestID,
                    compilation: snapshot(compilation),
                    generalizedParse: compilation.parseGeneralized(
                        try required(request.input, "input"), options: request.generalizedOptions ?? .init()
                    )
                )
            case .projectAnalyze, .semanticWorkspace:
                let manifest = try required(request.project, "project")
                let analysis = try await GrammarProjectWorkspace(manifest: manifest).analyze()
                let project = projectSnapshot(analysis)
                if request.operation == .semanticWorkspace {
                    return .init(
                        requestID: request.requestID,
                        project: project,
                        semanticWorkspace: analysis.semanticWorkspace(
                            schema: try required(request.semanticSchema, "semanticSchema")
                        )
                    )
                }
                return .init(requestID: request.requestID, project: project)
            case .languageKitValidate, .languageKitAnalyze:
                let kit = try GrammarSemanticLanguageKit.compile(
                    try required(request.languageKit, "languageKit")
                )
                let kitResult = GrammarToolingLanguageKitResult(
                    identifier: kit.manifest.identifier, name: kit.manifest.name,
                    version: kit.manifest.version,
                    fileExtensions: kit.manifest.fileExtensions,
                    semanticModel: kit.semanticModel,
                    passedTests: kit.conformance.passed,
                    failedTests: kit.conformance.failed,
                    isConformant: kit.isConformant
                )
                guard request.operation == .languageKitAnalyze else {
                    return .init(requestID: request.requestID, languageKit: kitResult)
                }
                let suppliedProject = try required(request.project, "project")
                let analysis = try await kit.analyze(
                    name: suppliedProject.name, sources: suppliedProject.sources
                )
                return .init(
                    requestID: request.requestID,
                    project: projectSnapshot(analysis.project),
                    semanticWorkspace: analysis.semantics,
                    languageKit: kitResult
                )
            case .graphLayout:
                return .init(
                    requestID: request.requestID,
                    graphLayout: try GrammarGraphLayoutEngine.layout(
                        try required(request.graph, "graph"),
                        options: request.graphLayoutOptions ?? .init()
                    )
                )
            case .graphValidate:
                let graph = try required(request.graph, "graph")
                let report: GrammarGraphCorrectnessReport
                let structural = GrammarGraphValidator.validate(graph)
                if structural.isValid && GrammarGraphLayoutEngine.availability == .swiftLayout {
                    let snapshot = try GrammarGraphLayoutEngine.layout(
                        graph, options: request.graphLayoutOptions ?? .init()
                    )
                    report = GrammarGraphValidator.validate(snapshot, against: graph)
                } else {
                    report = structural
                }
                return .init(requestID: request.requestID, graphCorrectness: report)
            case .graphMeasure:
                return .init(
                    requestID: request.requestID,
                    graphMeasuredLayout: try GrammarGraphMeasurementRunner.layout(
                        try required(request.graph, "graph"),
                        options: request.graphLayoutOptions ?? .init()
                    )
                )
            case .graphDOT:
                return .init(
                    requestID: request.requestID,
                    renderedGraph: GrammarGraphDOTRenderer.render(
                        try required(request.graph, "graph"),
                        options: request.graphLayoutOptions ?? .init()
                    )
                )
            case .graphGeometry:
                return .init(
                    requestID: request.requestID,
                    advancedGraphLayout: try GrammarGraphGeometryEngine.layout(
                        try required(request.graph, "graph"),
                        specification: request.graphGeometrySpecification ?? .init(),
                        options: request.graphLayoutOptions ?? .init()
                    )
                )
            case .portableGrammarImport:
                return .init(
                    requestID: request.requestID,
                    portableGrammar: try GrammarPortableInterchangeCodec.importGrammar(
                        try required(request.portableSource, "portableSource"),
                        notation: try required(request.portableNotation, "portableNotation"),
                        startSymbol: request.portableStartSymbol
                    )
                )
            case .portableGrammarRender:
                return .init(
                    requestID: request.requestID,
                    renderedGrammar: try GrammarPortableInterchangeCodec.render(
                        try required(request.portableGrammar, "portableGrammar"),
                        as: try required(request.portableRenderFormat, "portableRenderFormat")
                    )
                )
            case .bootstrapBundle:
                return .init(
                    requestID: request.requestID,
                    bootstrapBundle: try GrammarBootstrapInterchangeCodec.makeBundle(
                        options: request.bootstrapOptions ?? .init()
                    )
                )
            case .researchValidate:
                return .init(
                    requestID: request.requestID,
                    researchReport: try GrammarResearchValidator.run(
                        try required(request.researchProgramme, "researchProgramme")
                    )
                )
            case .selectedResearchPreview:
                let id = try required(request.researchStudyID, "researchStudyID")
                return .init(
                    requestID: request.requestID,
                    selectedResearchPreview: try GrammarSelectedResearchPreviewEngine.run(studyID: id)
                )
            case .sessionOpen, .sessionClose, .sessionStatus, .sessionReplaceGrammar,
                 .documentOpen, .documentChange, .documentClose, .cancel:
                return failure(
                    request, code: "stateful-service-required",
                    message: "This operation requires GrammarStatefulLanguageToolingService."
                )
            }
        } catch {
            return failure(request, code: "invalid-request", message: error.localizedDescription)
        }
    }

    private func required<Value>(_ value: Value?, _ name: String) throws -> Value {
        guard let value else { throw MissingPayload(name: name) }
        return value
    }

    private func failure(_ request: GrammarToolingRequest, code: String, message: String) -> GrammarToolingResponse {
        .init(requestID: request.requestID, status: .failure, error: .init(code: code, message: message))
    }

    private func snapshot(_ value: GrammarCompilation) -> GrammarToolingCompilationResult {
        .init(
            succeeded: value.succeeded, diagnostics: value.diagnostics, grammar: value.grammar,
            analysis: value.analysis, artifact: value.artifact, performance: value.performance
        )
    }

    private func projectSnapshot(_ value: GrammarProjectAnalysis) -> GrammarToolingProjectResult {
        let sources = Dictionary(uniqueKeysWithValues: value.manifest.sources.map { ($0.id, $0) })
        return .init(
            name: value.manifest.name, succeeded: value.isSuccessful,
            documents: value.documents.map {
                .init(
                    id: $0.documentID, path: sources[$0.documentID]?.path ?? $0.documentID,
                    revision: $0.text.revision, parseStatus: $0.parse.status,
                    lexicalDiagnosticCount: $0.lexing.diagnostics.count,
                    syntaxDiagnosticCount: $0.parse.diagnostics.count,
                    semanticEntryCount: $0.semanticIndex.entries.count
                )
            },
            index: value.index, passedTests: value.tests.passed, failedTests: value.tests.failed
        )
    }
}

private struct MissingPayload: LocalizedError {
    let name: String
    var errorDescription: String? { "The ‘\(name)’ payload is required for this operation." }
}

public enum GrammarToolingCodec {
    public static func encode(_ request: GrammarToolingRequest) throws -> Data { try encoder().encode(request) }
    public static func decodeRequest(_ data: Data) throws -> GrammarToolingRequest { try decoder().decode(GrammarToolingRequest.self, from: data) }
    public static func encode(_ response: GrammarToolingResponse) throws -> Data { try encoder().encode(response) }
    public static func decodeResponse(_ data: Data) throws -> GrammarToolingResponse { try decoder().decode(GrammarToolingResponse.self, from: data) }
    public static func encodeLine(_ request: GrammarToolingRequest) throws -> Data { try lineEncoder().encode(request) }
    public static func encodeLine(_ response: GrammarToolingResponse) throws -> Data { try lineEncoder().encode(response) }

    private static func encoder() -> JSONEncoder {
        let value = JSONEncoder()
        value.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return value
    }

    private static func decoder() -> JSONDecoder { JSONDecoder() }

    private static func lineEncoder() -> JSONEncoder {
        let value = JSONEncoder()
        value.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return value
    }
}

public protocol GrammarToolingTransport: Sendable {
    func send(_ request: Data) async throws -> Data
}

public struct GrammarInProcessToolingTransport: GrammarToolingTransport {
    private let service: GrammarLanguageToolingService

    public init(service: GrammarLanguageToolingService = .init()) { self.service = service }

    public func send(_ request: Data) async throws -> Data {
        try await GrammarToolingCodec.encode(service.handle(GrammarToolingCodec.decodeRequest(request)))
    }
}

public struct GrammarToolingClient: Sendable {
    private let transport: any GrammarToolingTransport

    public init(transport: any GrammarToolingTransport) { self.transport = transport }

    public func send(_ request: GrammarToolingRequest) async throws -> GrammarToolingResponse {
        let response = try GrammarToolingCodec.decodeResponse(
            await transport.send(GrammarToolingCodec.encode(request))
        )
        guard response.requestID == request.requestID else { throw GrammarToolingClientError.mismatchedRequestID }
        return response
    }
}

public enum GrammarToolingClientError: Error, LocalizedError, Sendable {
    case mismatchedRequestID
    public var errorDescription: String? { "The tooling response did not match the request identifier." }
}
