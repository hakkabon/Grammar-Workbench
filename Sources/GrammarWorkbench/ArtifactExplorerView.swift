#if os(macOS)
import SwiftUI
import AppKit

@MainActor
public struct ArtifactExplorerView: View {
    @State private var store: ExplorerStore
    @State private var tab = GrammarWorkbenchDestination.guide
    @State private var exportMessage: String?
    @State private var selectedTestID: UUID?
    @State private var exploresResolvedConflicts = false
    @State private var showsNavigation = true
    @State private var presentedDetail: ArtifactIdentity?
    @State private var transformationPreview: GrammarGuidedTransformationPreview?
    @State private var problemScope = ProblemScope.all
    @State private var loadedSourceProject: GrammarLoadedSourceProject?
    @State private var sourceProjectAnalysis: GrammarProjectAnalysis?
    @State private var sourceProjectSemantics: GrammarSemanticWorkspaceSnapshot?
    @State private var selectedSourceProjectDocumentID: String?
    @State private var isLoadingSourceProject = false
    @State private var sampleVisualization = SampleVisualization.trace
    private var document: Binding<GrammarWorkbenchDocument>?

    public init() {
        self.document = nil
        self._store = State(initialValue: ExplorerStore())
    }

    public init(document: Binding<GrammarWorkbenchDocument>, documentName: String = "Untitled") {
        self.document = document
        let value = document.wrappedValue
        let selectedInput = value.samples.first { $0.id == value.selectedSampleID }?.input ?? ""
        self._store = State(initialValue: ExplorerStore(
            source: value.source,
            algorithm: LRAlgorithm(rawValue: value.algorithm) ?? .lalr,
            notation: value.notation,
            sampleInput: selectedInput,
            documentName: documentName
        ))
    }

    enum ProblemScope: String, CaseIterable, Identifiable {
        case all = "All"
        case grammar = "Grammar"
        case sources = "Sources"
        case tests = "Tests"
        case semantics = "Semantics"
        var id: Self { self }

        func includes(_ problem: GrammarProjectExperienceProblem) -> Bool {
            switch self {
            case .all: true
            case .grammar: problem.area == .grammar
            case .sources: problem.area == .sources
            case .tests: problem.area == .tests
            case .semantics: problem.area == .semantics
            }
        }
    }

    enum SampleVisualization: String, CaseIterable, Identifiable {
        case trace = "Trace"
        case animated = "Animated graph"
        var id: Self { self }
    }

    public var body: some View {
        HSplitView {
            if showsNavigation {
                navigationSidebar
                    .frame(
                        minWidth: WorkbenchVisualFoundation.navigationMinimumWidth,
                        idealWidth: WorkbenchVisualFoundation.navigationIdealWidth,
                        maxWidth: WorkbenchVisualFoundation.navigationMaximumWidth,
                        maxHeight: .infinity
                    )
                    .accessibilityIdentifier("grammar-navigation-sidebar")
            }
            sourceSidebar
                .frame(
                    minWidth: WorkbenchVisualFoundation.sourceMinimumWidth,
                    idealWidth: WorkbenchVisualFoundation.sourceIdealWidth,
                    maxWidth: WorkbenchVisualFoundation.sourceMaximumWidth,
                    maxHeight: .infinity
                )
                .clipped()
                .accessibilityIdentifier("grammar-source-pane")
            VStack(spacing: 0) {
                selectedTab
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(
                minWidth: WorkbenchVisualFoundation.workspaceMinimumWidth,
                maxWidth: .infinity,
                maxHeight: .infinity
            )
            .accessibilityIdentifier("grammar-workspace-pane")
            .popover(isPresented: detailIsPresented, arrowEdge: .trailing) {
                contextualDetail
                    .frame(
                        minWidth: WorkbenchVisualFoundation.inspectorMinimumWidth,
                        idealWidth: WorkbenchVisualFoundation.inspectorIdealWidth,
                        maxWidth: WorkbenchVisualFoundation.inspectorMaximumWidth,
                        minHeight: 180,
                        idealHeight: 420,
                        maxHeight: 620
                    )
                    .accessibilityIdentifier("grammar-contextual-detail")
            }
        }
        .navigationTitle("Grammar Workbench")
        .toolbar {
            ToolbarItem {
                Button("Open Source Project", systemImage: "folder.badge.gearshape", action: openSourceProject)
                    .help("Open a .grammar-workbench-source.json project descriptor")
            }
            if document == nil {
                ToolbarItem {
                    Button("Open Grammar", systemImage: "folder", action: openGrammar)
                }
            }
            ToolbarItem {
                Picker("LR algorithm", selection: algorithmBinding) { ForEach(LRAlgorithm.allCases) { Text($0.rawValue).tag($0) } }
                    .frame(width: 180)
            }
            if store.isRegenerating {
                ToolbarItem { ProgressView().controlSize(.small).help("Regenerating grammar artifacts") }
            } else if let performance = store.constructionPerformance {
                ToolbarItem {
                    Text(performanceLabel(performance))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .help(performanceHelp(performance))
                }
            }
            ToolbarItem { Button("Export HTML", systemImage: "square.and.arrow.up", action: exportHTML) }
            ToolbarItem(placement: .navigation) {
                Toggle("Navigation", systemImage: "sidebar.left", isOn: $showsNavigation)
                    .help(showsNavigation ? "Hide navigation sidebar" : "Show navigation sidebar")
            }
            ToolbarItem {
                Menu("Interchange", systemImage: "arrow.left.arrow.right") {
                    if document != nil {
                        Button("Export Project JSON…", action: exportInterchange)
                        Button("Import Project JSON…", action: importInterchange)
                    }
                    Button("Export Artifact JSON…", action: exportArtifactInterchange)
                    Button("Export Semantic Model JSON…", action: exportSemanticModel)
                    Divider()
                    Button("Generate Swift Parser…", action: exportSwiftParser)
                    Button("Generate Portable BNF…", action: exportBNF)
                }
            }
        }
        .alert("Export", isPresented: Binding(get: { exportMessage != nil }, set: { if !$0 { exportMessage = nil } })) {
            Button("OK") { exportMessage = nil }
        } message: { Text(exportMessage ?? "") }
        .onChange(of: document?.wrappedValue.source) { _, source in
            if let source { store.updateSource(source) }
        }
        .onChange(of: document?.wrappedValue.notation) { _, notation in
            if let notation, store.notation != notation { store.notation = notation }
        }
        .onChange(of: tab) { _, _ in presentedDetail = nil }
    }

    private var navigationSidebar: some View {
        List(selection: $tab) {
            ForEach(GrammarWorkbenchNavigationSection.allCases) { section in
                Section(section.rawValue) {
                    ForEach(GrammarWorkbenchDestination.destinations(in: section)) { destination in
                        Label(destination.title, systemImage: destination.systemImage)
                            .tag(destination)
                            .accessibilityIdentifier("grammar-navigation-\(destination.rawValue)")
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Workspaces")
        .accessibilityLabel("Grammar Workbench navigation")
    }

    private func performanceLabel(_ performance: GrammarConstructionPerformance) -> String {
        switch performance.reuse {
        case .none: return String(format: "%.1f ms", performance.totalMilliseconds)
        case .cacheHit: return "Cached"
        case .coalesced: return "Shared"
        }
    }

    private func performanceHelp(_ performance: GrammarConstructionPerformance) -> String {
        String(
            format: "Front end %.2f ms · LR construction %.2f ms · %d states · %d items · %d table entries",
            performance.frontEndMilliseconds, performance.constructionMilliseconds,
            performance.stateCount, performance.itemCount, performance.tableEntryCount
        )
    }

    private var sourceSidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(store.documentName, systemImage: "doc.text")
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(store.notation.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                    .help(notationHelp)
                    .accessibilityLabel("Grammar notation: \(store.notation.displayName)")
            }
            .padding(.horizontal)
            GrammarSourceEditor(
                text: sourceBinding,
                diagnostics: store.frontEnd.diagnostics,
                selectedRange: store.sourceSelection,
                completions: GrammarEditorIntelligence.completions(for: store.frontEnd, notation: store.notation),
                isEditable: document != nil
            )
                .frame(minHeight: 280)
                .clipped()
                .accessibilityLabel(document == nil ? "Read-only grammar source" : "Editable grammar source")
                .contextMenu {
                    Menu("Interpret Grammar As") {
                        ForEach(GrammarSourceNotation.allCases) { notation in
                            Button {
                                notationBinding.wrappedValue = notation
                            } label: {
                                if notation == store.notation {
                                    Label(notation.displayName, systemImage: "checkmark")
                                } else {
                                    Text(notation.displayName)
                                }
                            }
                        }
                    }
                }
            Text("\(store.artifact.productions.count) productions · \(store.artifact.states.count) states")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            if !store.frontEnd.diagnostics.isEmpty {
                Divider()
                HStack {
                    Text("Diagnostics").font(.headline)
                    Spacer()
                    Text("\(store.frontEnd.diagnostics.count)").foregroundStyle(.secondary)
                }.padding(.horizontal)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 9) {
                        ForEach(store.frontEnd.diagnostics) { diagnostic in
                            Button { store.selectDiagnostic(diagnostic) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Label(diagnostic.message, systemImage: diagnostic.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                                        .foregroundStyle(diagnostic.severity == .error ? .red : .orange)
                                    Text("Line \(diagnostic.range.start.line), column \(diagnostic.range.start.column)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                            let fixes = GrammarEditorIntelligence.quickFixes(
                                for: diagnostic, source: sourceBinding.wrappedValue,
                                notation: store.notation
                            )
                            if !fixes.isEmpty, document != nil {
                                ForEach(fixes) { fix in
                                    Button(fix.title, systemImage: "wand.and.stars") { applyQuickFix(fix) }
                                        .buttonStyle(.link).font(.caption)
                                }
                            }
                        }
                    }.padding(.horizontal)
                }
                .frame(maxHeight: 190)
            }
        }.padding(.vertical)
    }

    private var notationHelp: String {
        switch store.notation {
        case .workbench: "Yacc-like grammar notation using directives and colon productions"
        case .ebnf: "ISO-style EBNF grammar notation"
        }
    }

    @ViewBuilder private var selectedTab: some View {
        switch tab {
        case .guide: guidedView
        case .project: projectView
        case .analysis: analysisView
        case .semantics: semanticsView
        case .comparison: comparisonView
        case .explore:
            InteractiveGrammarExplorerView(compilation: store.currentCompilationSnapshot) {
                store.selectSourceRange($0)
            }
        case .diagram:
            GrammarDiagramREPLView(compilation: store.currentCompilationSnapshot) {
                store.selectSourceRange($0)
            }
        case .automaton:
            AutomatonView(artifact: store.artifact, selection: store.selection) {
                presentDetail(.state($0))
            }
        case .table: tableView
        case .decisions: decisionsView
        case .sample: sampleView
        case .bootstrap: bootstrapView
        case .research: researchView
        case .visuals: GrammarVisualProductGalleryView(timeline: store.parserVisualizationTimeline)
        case .tests: testsView
        case .generation: generationView
        }
    }

    private var projectView: some View {
        let snapshot = sourceProjectAnalysis.map {
            GrammarProjectExperience.snapshot(
                analysis: $0,
                semantics: sourceProjectSemantics,
                operations: isLoadingSourceProject
                    ? [.init(kind: .loadingSourceProject, title: "Loading source project", detail: "Analyzing associated source files")]
                    : []
            )
        } ?? store.projectExperience(
            samples: document?.wrappedValue.samples ?? [.init(name: "Current example", input: store.sampleInput)],
            tests: document?.wrappedValue.tests ?? []
        )
        let visibleProblems = snapshot.problems.filter(problemScope.includes)
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 18) {
                    Image(systemName: snapshot.errorCount == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(snapshot.errorCount == 0 ? .green : .orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(snapshot.name).font(.title2.bold())
                        Text(snapshot.errorCount == 0
                             ? "The language project is ready for testing and generation."
                             : "Resolve the project problems below before generating a parser.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("\(snapshot.healthScore)").font(.title.bold()).monospacedDigit()
                        Text("Health").font(.caption).foregroundStyle(.secondary)
                    }
                }

                if !snapshot.operations.isEmpty {
                    GroupBox("Background work") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(snapshot.operations) { operation in
                                HStack(spacing: 10) {
                                    ProgressView().controlSize(.small)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(operation.title).font(.subheadline.bold())
                                        Text(operation.detail).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let loadedSourceProject, let sourceProjectAnalysis {
                    sourceProjectSection(loadedSourceProject, analysis: sourceProjectAnalysis)
                }

                Text("Project navigator").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(snapshot.navigator) { item in
                        Button { follow(item.destination) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: projectIcon(item.area)).font(.title2).foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title).font(.headline)
                                    Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer()
                                Text("\(item.count)").font(.headline.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            .padding().frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain)
                    }
                }

                HStack {
                    Text("Problems").font(.headline)
                    Text("\(snapshot.problems.count)").foregroundStyle(.secondary)
                    Spacer()
                    Picker("Problem scope", selection: $problemScope) {
                        ForEach(ProblemScope.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).frame(maxWidth: 470)
                }
                if visibleProblems.isEmpty {
                    ContentUnavailableView(
                        "No problems in this category", systemImage: "checkmark.circle",
                        description: Text("Grammar, examples, tests, and semantic services share this problem list.")
                    )
                    .frame(minHeight: 180)
                } else {
                    VStack(spacing: 0) {
                        ForEach(visibleProblems) { problem in
                            Button { follow(problem) } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: problemIcon(problem.severity))
                                        .foregroundStyle(problemColor(problem.severity))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(problem.title).font(.subheadline.bold())
                                        Text(problem.detail).font(.caption).foregroundStyle(.secondary)
                                        if let path = problem.path {
                                            Text(path).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                                        }
                                    }
                                    Spacer()
                                    Text(problem.area.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                }
                                .padding(12).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(24).frame(maxWidth: 1050, alignment: .leading)
        }
    }

    private func sourceProjectSection(
        _ loaded: GrammarLoadedSourceProject,
        analysis: GrammarProjectAnalysis
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Associated source files", systemImage: "doc.on.doc")
                    .font(.headline)
                Spacer()
                Text(loaded.descriptor.grammar.languageID)
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Text(loaded.descriptorURL.path)
                .font(.caption2.monospaced()).foregroundStyle(.tertiary)
                .textSelection(.enabled)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(loaded.manifest.sources) { source in
                        let result = analysis.documents.first { $0.documentID == source.id }
                        Button {
                            selectedSourceProjectDocumentID = source.id
                        } label: {
                            HStack {
                                Image(systemName: sourceProjectStatusIcon(result))
                                    .foregroundStyle(sourceProjectStatusColor(result))
                                Text(source.path).font(.system(.caption, design: .monospaced))
                                Spacer()
                            }
                            .padding(7)
                            .background(
                                selectedSourceProjectDocumentID == source.id
                                    ? Color.accentColor.opacity(0.14) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Source file \(source.path)")
                    }
                }
                .frame(minWidth: 220, idealWidth: 280, maxWidth: 340, alignment: .topLeading)

                if let source = selectedSourceProjectSource(in: loaded.manifest) {
                    ScrollView([.horizontal, .vertical]) {
                        Text(source.text)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(10)
                    }
                    .frame(minHeight: 150, maxHeight: 280)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator.opacity(0.7)))
                    .accessibilityLabel("Source preview for \(source.path)")
                } else {
                    ContentUnavailableView("Select a source file", systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity, minHeight: 150)
                }
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func selectedSourceProjectSource(in manifest: GrammarProjectManifest) -> GrammarProjectSource? {
        let id = selectedSourceProjectDocumentID ?? manifest.sources.first?.id
        return manifest.sources.first { $0.id == id }
    }

    private func sourceProjectStatusIcon(_ result: GrammarIncrementalAnalysisSnapshot?) -> String {
        guard let result else { return "clock" }
        return result.lexing.diagnostics.isEmpty && result.parse.status == .accepted
            ? "checkmark.circle.fill" : "xmark.octagon.fill"
    }

    private func sourceProjectStatusColor(_ result: GrammarIncrementalAnalysisSnapshot?) -> Color {
        guard let result else { return .secondary }
        return result.lexing.diagnostics.isEmpty && result.parse.status == .accepted ? .green : .red
    }

    private func projectIcon(_ area: GrammarProjectExperienceArea) -> String {
        switch area {
        case .grammar: "text.book.closed"
        case .sources: "doc.on.doc"
        case .tests: "checklist"
        case .semantics: "point.3.connected.trianglepath.dotted"
        case .generation: "hammer"
        }
    }

    private func problemIcon(_ severity: GrammarProjectExperienceSeverity) -> String {
        switch severity {
        case .error: "xmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .information: "info.circle.fill"
        }
    }

    private func problemColor(_ severity: GrammarProjectExperienceSeverity) -> Color {
        switch severity { case .error: .red; case .warning: .orange; case .information: .blue }
    }

    private func follow(_ problem: GrammarProjectExperienceProblem) {
        if let documentID = problem.documentID,
           loadedSourceProject?.manifest.sources.contains(where: { $0.id == documentID }) == true {
            selectedSourceProjectDocumentID = documentID
            tab = .project
            return
        }
        store.selectProjectProblem(problem)
        follow(problem.destination)
    }

    private func follow(_ destination: GrammarProjectExperienceDestination) {
        switch destination {
        case .editor: break
        case .guide: tab = .guide
        case .analysis: tab = .analysis
        case .semantics: tab = .semantics
        case .generation: tab = .generation
        case .decisions: tab = .decisions
        case .sample: tab = .sample
        case .tests: tab = .tests
        }
    }

    private var semanticsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("Semantic model", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.title2.bold())
                Text("Production identities connect syntax trees, generated semantic actions, and workspace services without coupling them to parser internals.")
                    .foregroundStyle(.secondary)
                if let model = try? GrammarSemanticModel(compilation: store.currentCompilationSnapshot) {
                    HStack(spacing: 24) {
                        semanticMetric("Productions", model.productions.count)
                        semanticMetric("Nonterminals", model.nonterminals.count)
                        semanticMetric("Terminals", model.terminals.count)
                        semanticMetric("Indexed nodes", store.incrementalSampleAnalysis?.semanticIndex.entries.count ?? 0)
                    }
                    Divider()
                    Text("Productions available to semantic actions").font(.headline)
                    ForEach(model.productions) { production in
                        Button("\(production.id): \(production.text)") {
                            presentDetail(.production(.init(rawValue: production.id)))
                        }
                        .buttonStyle(.plain).font(.system(.body, design: .monospaced))
                    }
                    if let snapshot = store.incrementalSampleAnalysis {
                        Divider()
                        Text("Current example index").font(.headline)
                        Text("Revision \(snapshot.text.revision) · \(snapshot.semanticIndex.entries.count) entries · \(snapshot.incrementalIndexing.reusedEntries) reused")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("Export semantic model…", systemImage: "square.and.arrow.up") {
                            exportSemanticModel()
                        }
                        Button("Generate semantic actions…", systemImage: "swift") {
                            exportSemanticSwift()
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "Semantic model unavailable", systemImage: "exclamationmark.triangle",
                        description: Text("Correct grammar errors before configuring semantics.")
                    )
                }
            }.padding(24).frame(maxWidth: 1000, alignment: .leading)
        }
    }

    private func semanticMetric(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(.title3.bold()).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var generationView: some View {
        let unresolved = store.artifact.decisions.filter { $0.disposition == .unresolved }.count
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("Generate and share", systemImage: "hammer").font(.title2.bold())
                Text("All generated outputs use the same validated grammar and stable public snapshots shown throughout the workbench.")
                    .foregroundStyle(.secondary)
                if store.frontEnd.hasErrors || unresolved > 0 {
                    Label(
                        store.frontEnd.hasErrors
                            ? "Correct grammar errors before generation"
                            : "Resolve \(unresolved) parser decision\(unresolved == 1 ? "" : "s") before generation",
                        systemImage: "exclamationmark.triangle.fill"
                    ).foregroundStyle(.orange).font(.headline)
                } else {
                    Label("Ready to generate", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green).font(.headline)
                }
                generationCard(
                    "Standalone Swift parser", "Lexer, parser tables, recovery, syntax nodes, and no runtime Workbench dependency.",
                    "swift", enabled: !store.frontEnd.hasErrors && unresolved == 0, action: exportSwiftParser
                )
                generationCard(
                    "Semantic action starter", "Editable production-complete reducer scaffolding for a typed application model.",
                    "point.3.connected.trianglepath.dotted", enabled: !store.frontEnd.hasErrors, action: exportSemanticSwift
                )
                generationCard(
                    "Portable BNF", "Canonical BNF output for interchange, review, and bootstrap experiments.",
                    "text.book.closed", enabled: !store.frontEnd.hasErrors, action: exportBNF
                )
                generationCard(
                    "Artifact and HTML reports", "Versioned machine-readable snapshots or a standalone interactive engineering report.",
                    "square.and.arrow.up", enabled: !store.frontEnd.hasErrors, action: exportHTML
                )
            }.padding(24).frame(maxWidth: 900, alignment: .leading)
        }
    }

    private func generationCard(
        _ title: String, _ description: String, _ icon: String,
        enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundStyle(.tint).frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Create…", action: action).disabled(!enabled)
        }
        .padding().background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    private var bootstrapView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("Bootstrap laboratory", systemImage: "arrow.triangle.2.circlepath").font(.title2.bold())
                Text("Compile the trusted BNF seed, parse its own meta-grammar, regenerate the parser, and compare canonical grammar models until they reach a fixed point.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Run self-hosting experiment", systemImage: "play.fill") { store.runBootstrapLaboratory() }
                        .disabled(store.isRunningBootstrap)
                    if store.isRunningBootstrap { ProgressView().controlSize(.small) }
                }
                if let error = store.bootstrapError {
                    Label(error, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                }
                if let report = store.bootstrapReport {
                    Label(
                        report.succeeded ? "Fixed point and differential checks passed" : "Experiment did not satisfy every gate",
                        systemImage: report.succeeded ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                    ).foregroundStyle(report.succeeded ? .green : .orange).font(.headline)
                    LabeledContent("Profile", value: report.profile)
                    LabeledContent("Fixed-point generation", value: report.fixedPointGeneration.map(String.init) ?? "Not reached")
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                        GridRow { Text("Generation").bold(); Text("Grammar").bold(); Text("Artifact").bold(); Text("States").bold(); Text("Stable").bold() }
                        ForEach(report.generations) { generation in
                            GridRow {
                                Text("\(generation.generation)").monospacedDigit()
                                Text(generation.grammarFingerprint).font(.system(.caption, design: .monospaced))
                                Text(generation.artifactFingerprint).font(.system(.caption, design: .monospaced))
                                Text("\(generation.stateCount)").monospacedDigit()
                                Image(systemName: generation.stableWithPrevious ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(generation.stableWithPrevious ? .green : .secondary)
                            }
                        }
                    }
                    Divider()
                    Text("Differential corpus").font(.headline)
                    ForEach(report.corpus) { item in
                        HStack {
                            Label(item.name, systemImage: item.matches ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(item.matches ? .green : .red)
                            Spacer()
                            Text(item.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    DisclosureGroup("Laboratory boundaries") {
                        ForEach(report.limitations, id: \.self) { Text("• \($0)").font(.caption) }
                    }
                } else if !store.isRunningBootstrap {
                    ContentUnavailableView("Experiment not run", systemImage: "flask", description: Text("The trusted grammar reader is never replaced by this experiment."))
                }
            }.padding().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var guidedView: some View {
        let report = store.guidance(tests: document?.wrappedValue.tests ?? [])
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 24) {
                    ZStack {
                        Circle().stroke(.quaternary, lineWidth: 10)
                        Circle()
                            .trim(from: 0, to: Double(report.summary.healthScore) / 100)
                            .stroke(healthColor(report.summary), style: .init(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text("\(report.summary.healthScore)").font(.title.bold()).monospacedDigit()
                            Text("Health").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 112, height: 112)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(report.summary.headline).font(.title2.bold())
                        Text("Start with the first recommended action. Detailed parser machinery remains available in the Expert section of the navigation sidebar.")
                            .foregroundStyle(.secondary)
                        HStack(spacing: 16) {
                            guidanceMetric("Errors", report.summary.errors, .red)
                            guidanceMetric("Warnings", report.summary.warnings, .orange)
                            guidanceMetric("Conflicts", report.summary.unresolvedConflicts, .red)
                            guidanceMetric("Tests passing", report.summary.passingTests, .green)
                        }
                    }
                }

                if let next = report.nextAction {
                    GroupBox("Recommended next step") {
                        guidanceRow(next, prominent: true)
                            .padding(.vertical, 4)
                    }
                }

                Text("Your workflow").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                    workflowCard("Write and validate", "Correct grammar declarations and inspect plain-language diagnostics.", "pencil.and.outline", .analysis)
                    workflowCard("Try an input", "See whether an example is accepted and understand any recovery.", "play.circle", .sample)
                    workflowCard("Resolve ambiguity", "Compare competing interpretations and their example input.", "arrow.triangle.branch", .decisions)
                    workflowCard("Protect behavior", "Record accepted, rejected, and conflicting examples as tests.", "checklist", .tests)
                    workflowCard("Choose an algorithm", "Compare parser size and unresolved decisions.", "scale.3d", .comparison)
                    workflowCard("Generate a parser", "Export a standalone Swift parser when the grammar is ready.", "hammer", .analysis)
                }

                if report.findings.count > 1 {
                    DisclosureGroup("All recommendations (\(report.findings.count))") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(report.findings) { guidanceRow($0, prominent: false) }
                        }.padding(.top, 8)
                    }
                }

                if let structural = store.structuralAnalysis() {
                    DisclosureGroup("Grammar structure") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(structural.statistics.nonterminals) nonterminals · \(structural.statistics.terminals) terminals · \(structural.statistics.productions) productions · \(structural.statistics.dependencyEdges) dependencies")
                                .font(.caption.monospacedDigit())
                            structuralSet("Nullable", structural.nullableNonterminals)
                            structuralSet("Unreachable", structural.unreachableNonterminals)
                            structuralSet("Unproductive", structural.unproductiveNonterminals)
                            structuralSet("Directly left-recursive", structural.directlyLeftRecursiveNonterminals)
                            if !structural.indirectlyLeftRecursiveComponents.isEmpty {
                                Text("Indirect left recursion: \(structural.indirectlyLeftRecursiveComponents.map { $0.joined(separator: " ↔ ") }.joined(separator: "; "))")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }.padding(.top, 8)
                    }
                }

                if store.notation == .workbench && cleanupTransformations.isEmpty == false {
                    Divider()
                    Text("Safe change preview").font(.headline)
                    Text("Grammar Workbench proposes a source change, recompiles it, and checks your samples and tests before enabling Apply.")
                        .foregroundStyle(.secondary)
                    HStack {
                        ForEach(cleanupTransformations, id: \.self) { transformation in
                            Button(transformation.title, systemImage: "wand.and.stars") {
                                transformationPreview = store.preview(
                                    transformation,
                                    examples: guidedExamples,
                                    tests: document?.wrappedValue.tests ?? []
                                )
                            }
                        }
                    }
                    if let preview = transformationPreview { transformationPreviewView(preview) }
                }
            }
            .padding(24)
            .frame(maxWidth: 1000, alignment: .leading)
        }
    }

    private var cleanupTransformations: [GrammarGuidedTransformation] {
        store.availableGuidedTransformations()
    }

    private var guidedExamples: [GrammarGuidanceExample] {
        (document?.wrappedValue.samples ?? []).map {
            .init(id: $0.id.uuidString, name: $0.name, input: $0.input)
        }
    }

    private func healthColor(_ summary: GrammarGuidanceSummary) -> Color {
        if summary.errors > 0 || summary.unresolvedConflicts > 0 { return .red }
        if summary.warnings > 0 || summary.failingTests > 0 { return .orange }
        return .green
    }

    private func guidanceMetric(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(.headline.monospacedDigit()).foregroundStyle(value == 0 ? .secondary : color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func structuralSet(_ label: String, _ values: [String]) -> some View {
        if !values.isEmpty {
            Text("\(label): \(values.joined(separator: ", "))")
                .font(.caption).foregroundStyle(label == "Nullable" ? Color.secondary : Color.orange)
        }
    }

    private func guidanceRow(_ finding: GrammarGuidanceFinding, prominent: Bool) -> some View {
        Button { follow(finding) } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: guidanceIcon(finding.severity))
                    .foregroundStyle(guidanceColor(finding.severity)).font(prominent ? .title2 : .body)
                VStack(alignment: .leading, spacing: 4) {
                    Text(finding.title).font(prominent ? .headline : .subheadline.bold())
                    Text(finding.explanation).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(finding.action).font(.caption.bold()).foregroundStyle(.tint)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func workflowCard(
        _ title: String, _ description: String, _ icon: String,
        _ destination: GrammarWorkbenchDestination
    ) -> some View {
        Button { tab = destination } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.title2).foregroundStyle(.tint)
                Text(title).font(.headline)
                Text(description).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding().frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }

    private func follow(_ finding: GrammarGuidanceFinding) {
        store.selectGuidance(finding)
        switch finding.destination {
        case .editor: break
        case .analysis, .generation: tab = .analysis
        case .sample: tab = .sample
        case .decisions: tab = .decisions
        case .comparison: tab = .comparison
        case .tests: tab = .tests
        case .research: tab = .research
        }
    }

    private func guidanceIcon(_ severity: GrammarGuidanceSeverity) -> String {
        switch severity {
        case .critical: "xmark.octagon.fill"
        case .attention: "exclamationmark.triangle.fill"
        case .opportunity: "lightbulb.fill"
        case .ready: "checkmark.seal.fill"
        }
    }

    private func guidanceColor(_ severity: GrammarGuidanceSeverity) -> Color {
        switch severity {
        case .critical: .red
        case .attention: .orange
        case .opportunity: .blue
        case .ready: .green
        }
    }

    private func transformationPreviewView(_ preview: GrammarGuidedTransformationPreview) -> some View {
        GroupBox(preview.transformation.title) {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    preview.isSafeToApply ? "Validation passed" : "Review required before applying",
                    systemImage: preview.isSafeToApply ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
                ).foregroundStyle(preview.isSafeToApply ? .green : .orange)
                Text("Removes source line\(preview.removedLines.count == 1 ? "" : "s") \(preview.removedLines.map(String.init).joined(separator: ", ")).")
                    .font(.caption)
                if let diff = preview.artifactDiff {
                    Text("Parser impact: \(signed(diff.stateDelta)) states · \(signed(diff.tableEntryDelta)) table entries · \(signed(diff.decisionDelta)) decisions")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                if let plan = preview.plan {
                    Text(plan.explanation).font(.caption).foregroundStyle(.secondary)
                }
                if let behavior = preview.behavior {
                    Text("Behavior check: \(behavior.cases.count) inputs · \(behavior.discrepancies.count) membership differences. \(behavior.conclusion)")
                        .font(.caption).foregroundStyle(behavior.agreesOnCorpus ? Color.secondary : Color.red)
                }
                if !preview.regressedExamples.isEmpty {
                    Text("\(preview.regressedExamples.count) previously accepted sample(s) would stop working.").foregroundStyle(.red)
                } else if !preview.changedExamples.isEmpty {
                    Text("\(preview.changedExamples.count) sample outcome(s) improve or otherwise change.").foregroundStyle(.orange)
                }
                HStack {
                    Button("Discard") { transformationPreview = nil }
                    Button("Apply to grammar") { apply(preview) }
                        .buttonStyle(.borderedProminent).disabled(!preview.isSafeToApply || document == nil)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func apply(_ preview: GrammarGuidedTransformationPreview) {
        sourceBinding.wrappedValue = preview.proposedSource
        store.updateSource(preview.proposedSource)
        transformationPreview = nil
    }

    private var comparisonView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if store.isComparingAlgorithms {
                    HStack { ProgressView(); Text("Constructing and comparing all LR algorithms…") }
                } else if let comparison = store.algorithmComparison {
                    Label(
                        "Recommended: \(comparison.recommendedAlgorithm.rawValue)",
                        systemImage: "checkmark.seal.fill"
                    )
                    .font(.headline).foregroundStyle(.green)
                    Text(comparison.recommendation).foregroundStyle(.secondary)

                    Text("Construction metrics").font(.headline)
                    VStack(spacing: 7) {
                        HStack {
                            Text("Algorithm").bold().frame(maxWidth: .infinity, alignment: .leading)
                            Text("States").bold(); Text("Edges").bold(); Text("Entries").bold()
                            Text("Conflicts").bold(); Text("Resolved").bold()
                        }
                        ForEach(comparison.algorithmMetrics, id: \GrammarAlgorithmMetrics.algorithm) { (metric: GrammarAlgorithmMetrics) in
                            HStack {
                                Text(metric.algorithm.rawValue).frame(maxWidth: .infinity, alignment: .leading)
                                Text("\(metric.states)"); Text("\(metric.transitions)")
                                Text("\(metric.tableEntries)"); Text("\(metric.unresolvedConflicts)")
                                    .foregroundStyle(metric.unresolvedConflicts == 0 ? Color.secondary : Color.red)
                                Text("\(metric.resolvedDecisions)")
                            }
                        }
                    }

                    let merges = comparison.stateCorrespondences.filter(\.isCanonicalMerge)
                    Divider()
                    Text("Canonical state merging").font(.headline)
                    if merges.isEmpty {
                        Text("No canonical LR(1) states share an LR(0) core.").foregroundStyle(.secondary)
                    } else {
                        Text("\(merges.count) LALR state group(s) merge canonical states.")
                            .foregroundStyle(.secondary)
                        ForEach(merges) { correspondence in
                            comparisonStateRow(correspondence)
                        }
                    }

                    Divider()
                    Text("Table differences").font(.headline)
                    if comparison.tableDifferences.isEmpty {
                        Text("All corresponding cells have equivalent actions.").foregroundStyle(.secondary)
                    } else {
                        Text("\(comparison.tableDifferences.count) corresponding cell(s) differ.")
                            .foregroundStyle(.secondary)
                        ForEach(comparison.tableDifferences.prefix(250)) { difference in
                            comparisonDifferenceRow(difference)
                        }
                        if comparison.tableDifferences.count > 250 {
                            Text("Showing the first 250 differences.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else if store.frontEnd.hasErrors {
                    ContentUnavailableView("Grammar has errors", systemImage: "exclamationmark.triangle")
                } else {
                    Button("Compare algorithms", systemImage: "arrow.triangle.branch") {
                        store.compareAlgorithms()
                    }
                }
            }
            .padding().frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { store.compareAlgorithms() }
    }

    private func comparisonStateRow(_ correspondence: GrammarStateCorrespondence) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                algorithmStateLinks("SLR", states: correspondence.slrStates)
                algorithmStateLinks("LALR", states: correspondence.lalrStates)
                algorithmStateLinks("Canonical", states: correspondence.canonicalStates)
            }
            Text(correspondence.coreItems.joined(separator: " · "))
                .font(.system(.caption, design: .monospaced)).lineLimit(2).foregroundStyle(.secondary)
        }
        .padding(8).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    private func algorithmStateLinks(_ label: String, states: [Int]) -> some View {
        HStack(spacing: 3) {
            Text("\(label):").bold()
            ForEach(states, id: \.self) { state in
                Button("I\(state)") {
                    store.selectComparisonState(algorithm: comparisonAlgorithm(label), state: state)
                }.buttonStyle(.link)
            }
        }.font(.caption)
    }

    private func comparisonDifferenceRow(_ difference: GrammarTableDifference) -> some View {
        HStack(alignment: .top) {
            Label(difference.symbol, systemImage: difference.kind == .conflict ? "exclamationmark.triangle.fill" : "arrow.left.arrow.right")
                .foregroundStyle(difference.kind == .conflict ? .red : .primary)
                .frame(width: 120, alignment: .leading)
            comparisonCells("SLR", difference.slr, symbol: difference.symbol)
            comparisonCells("LALR", difference.lalr, symbol: difference.symbol)
            comparisonCells("Canonical", difference.canonical, symbol: difference.symbol)
        }
        .font(.caption).padding(.vertical, 4)
    }

    private func comparisonCells(_ label: String, _ cells: [GrammarComparedCell], symbol: String) -> some View {
        VStack(alignment: .leading) {
            Text(label).bold()
            ForEach(cells) { cell in
                let value = "I\(cell.state): \(cell.actions.map(\.label).joined(separator: " / "))"
                Button(value) {
                    store.selectComparisonCell(
                        algorithm: comparisonAlgorithm(label), state: cell.state, symbol: symbol
                    )
                }.buttonStyle(.link)
            }
            if cells.isEmpty { Text("—").foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func comparisonAlgorithm(_ label: String) -> GrammarAlgorithm {
        switch label { case "SLR": .slr; case "Canonical": .canonical; default: .lalr }
    }

    private var analysisView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let grammar = store.frontEnd.grammar, let analysis = store.frontEnd.analysis {
                    validationSummary(grammar)
                    Divider()
                    LabeledContent("Start symbol", value: grammar.startSymbol)
                    LabeledContent("Source notation", value: store.notation.displayName)
                    if let difference = store.latestArtifactDiff {
                        DisclosureGroup("Impact of latest valid edit") {
                            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 5) {
                                GridRow { Text("States"); Text(signed(difference.stateDelta)) }
                                GridRow { Text("Transitions"); Text(signed(difference.transitionDelta)) }
                                GridRow { Text("Table entries"); Text(signed(difference.tableEntryDelta)) }
                                GridRow { Text("Decisions"); Text(signed(difference.decisionDelta)) }
                            }
                            .font(.caption.monospacedDigit())
                            if !difference.addedProductions.isEmpty {
                                Text("Added: \(difference.addedProductions.joined(separator: " · "))")
                                    .font(.caption).foregroundStyle(.green)
                            }
                            if !difference.removedProductions.isEmpty {
                                Text("Removed: \(difference.removedProductions.joined(separator: " · "))")
                                    .font(.caption).foregroundStyle(.red)
                            }
                        }
                    }
                    if store.notation == .ebnf,
                       let lowering = try? GrammarWorkbenchAPI.lowerEBNF(sourceBinding.wrappedValue) {
                        DisclosureGroup("Lowered BNF (\(lowering.syntheticNonterminals.count) synthetic symbols)") {
                            ScrollView(.horizontal) {
                                Text(lowering.loweredSource)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.top, 6)
                        }
                    }
                    LabeledContent(
                        "Terminal mode",
                        value: grammar.lexerRules.isEmpty
                            ? (grammar.usesExplicitTokens ? "Explicit tokens" : "Inferred (legacy)")
                            : "Integrated lexer"
                    )
                    if !grammar.lexerRules.isEmpty {
                        if let lexerAnalysis = store.frontEnd.lexerAnalysis {
                            LabeledContent("Lexer modes", value: lexerAnalysis.modes.joined(separator: ", "))
                            LabeledContent("Reachable modes", value: lexerAnalysis.reachableModes.joined(separator: ", "))
                        }
                        Text("Lexer rules (declaration order)").font(.headline)
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                            GridRow { Text("Mode").bold(); Text("Emits").bold(); Text("Pattern").bold(); Text("Action").bold() }
                            ForEach(grammar.lexerRules) { rule in
                                GridRow {
                                    Text(rule.mode).font(.system(.body, design: .monospaced))
                                    Text(rule.token ?? "skip").foregroundStyle(rule.isSkipped ? .secondary : .primary)
                                    Text("/\(rule.pattern)/").font(.system(.body, design: .monospaced)).textSelection(.enabled)
                                    Text(lexerActionLabel(rule.action)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Text("Productions").font(.headline)
                    ForEach(grammar.productions) { production in
                        Button(production.text) {
                            presentDetail(.production(.init(rawValue: production.id + 1)))
                        }
                        .buttonStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                    }
                    Divider()
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                        GridRow {
                            Text("Symbol").bold()
                            Text("Nullable").bold()
                            Text("FIRST").bold()
                            Text("FOLLOW").bold()
                        }
                        ForEach(grammar.nonterminals, id: \.self) { symbol in
                            GridRow {
                                Text(symbol).font(.system(.body, design: .monospaced))
                                Image(systemName: analysis.nullable.contains(symbol) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(analysis.nullable.contains(symbol) ? .green : .secondary)
                                setText(analysis.first[symbol, default: []])
                                setText(analysis.follow[symbol, default: []])
                            }
                        }
                    }
                    if !grammar.precedence.isEmpty {
                        Divider()
                        Text("Precedence (low to high)").font(.headline)
                        ForEach(grammar.precedence, id: \.level) { declaration in
                            LabeledContent("\(declaration.level). \(declaration.associativity.rawValue)", value: declaration.symbols.joined(separator: ", "))
                        }
                    }
                } else {
                    ContentUnavailableView("Grammar has errors", systemImage: "exclamationmark.triangle", description: Text("Correct the listed diagnostics before analysis can continue."))
                }
            }.padding().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func validationSummary(_ grammar: ParsedGrammar) -> some View {
        let errors = store.frontEnd.diagnostics.filter { $0.severity == .error }.count
        let warnings = store.frontEnd.diagnostics.filter { $0.severity == .warning }.count
        return HStack(spacing: 18) {
            Label(errors == 0 ? "Valid grammar" : "\(errors) errors",
                  systemImage: errors == 0 ? "checkmark.seal.fill" : "xmark.octagon.fill")
                .foregroundStyle(errors == 0 ? .green : .red)
            Label("\(warnings) warnings", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(warnings == 0 ? Color.secondary : Color.orange)
            Spacer()
            Text("\(grammar.nonterminals.count) nonterminals · \(grammar.terminals.count) terminals")
                .foregroundStyle(.secondary)
        }
    }

    private func setText(_ values: Set<String>) -> some View {
        Text("{ \(values.sorted().joined(separator: ", ")) }")
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
    }

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }

    private func lexerActionLabel(_ action: LexerModeAction) -> String {
        switch action {
        case .none: "—"
        case .begin(let mode): "begin \(mode)"
        case .push(let mode): "push \(mode)"
        case .pop: "pop"
        }
    }

    private var tableView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                decisionLegend("Unresolved", color: .red)
                decisionLegend("Resolved", color: .blue)
                decisionLegend("Expected", color: .green)
                Spacer()
                Text("Decision cells show the effective action; inspect them for original alternatives.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(10)
            Divider()
            ScrollView([.horizontal, .vertical]) {
                Grid(horizontalSpacing: 1, verticalSpacing: 1) {
                    GridRow {
                        tableText("State", header: true)
                        ForEach(store.artifact.terminals + store.artifact.nonterminals, id: \.self) { tableText($0, header: true) }
                    }
                    ForEach(store.artifact.states) { state in
                        GridRow {
                            tableStateCell(state.id)
                            ForEach(store.artifact.terminals + store.artifact.nonterminals, id: \.self) { symbol in
                                parsingTableCell(.init(state: state.id, symbol: symbol))
                            }
                        }
                    }
                }.padding()
            }
        }
    }

    private func decisionLegend(_ label: String, color: Color) -> some View {
        Label { Text(label).font(.caption) } icon: {
            Circle().fill(color).frame(width: 9, height: 9)
        }
    }

    private func tableStateCell(_ state: StateID) -> some View {
        let summary = store.artifact.decisionSummary(for: state)
        return Button(state.description) { presentDetail(.state(state)) }
            .frame(width: 60, height: 32)
            .background(summary.map { dispositionColor($0.disposition).opacity(0.17) } ?? Color(nsColor: .controlBackgroundColor))
            .help(summary.map { "\($0.disposition.label): \($0.decisions.count) decision\($0.decisions.count == 1 ? "" : "s")" } ?? "No decisions")
    }

    private func parsingTableCell(_ id: CellID) -> some View {
        let cell = store.artifact.cell(id)
        let decision = store.artifact.decision(at: id)
        let effective = cell?.actions.map(\.label).joined(separator: "/") ?? (decision == nil ? "" : "error")
        let candidates = decision.map { store.artifact.candidateActions(for: $0).map(\.label).joined(separator: " / ") } ?? ""
        let description = decision.map {
            "\($0.disposition.label). Candidates: \(candidates). Effective: \(effective)."
        } ?? "State \(id.state.rawValue), symbol \(id.symbol), \(effective.isEmpty ? "empty" : effective)"
        return Button { presentDetail(.cell(id)) } label: {
            HStack(spacing: 4) {
                Text(effective)
                if let decision {
                    Image(systemName: decisionIcon(decision)).font(.system(size: 9, weight: .bold))
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .frame(width: 74, height: 32)
        .background(decision.map { dispositionColor($0.disposition).opacity(0.20) }
            ?? (cell?.isConflict == true ? Color.red.opacity(0.22) : Color(nsColor: .controlBackgroundColor)))
        .help(description)
        .accessibilityLabel(description)
    }

    private func tableText(_ text: String, header: Bool) -> some View {
        Text(text).font(header ? .headline : .body).frame(width: 74, height: 32).background(Color(nsColor: .controlBackgroundColor))
    }

    private var decisionsView: some View {
        VStack(spacing: 0) {
            if let expectation = store.artifact.conflictExpectation {
                Label(
                    expectation.matches
                        ? "%expect \(expectation.expected) matches generated conflicts"
                        : "%expect \(expectation.expected), but generated \(expectation.actual)",
                    systemImage: expectation.matches ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(expectation.matches ? .green : .orange)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                Divider()
            }
            List(store.artifact.decisions) { decision in
                Button { presentDetail(.decision(decision.id)) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(decision.title, systemImage: decisionIcon(decision))
                            .foregroundStyle(decisionColor(decision))
                        if !decision.witness.isEmpty {
                            Text("\(decision.disposition == .resolved ? "Decision trigger" : "Counterexample"): \(decision.witness.joined(separator: " "))")
                                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 5)
                }.buttonStyle(.plain)
            }.overlay { if store.artifact.decisions.isEmpty { ContentUnavailableView("No decisions", systemImage: "checkmark.seal") } }
        }
    }

    private func decisionIcon(_ decision: ConflictDecision) -> String {
        if decision.isExpected { return "checkmark.seal.fill" }
        if let kind = decision.provenance?.kind, kind != .unresolved { return "arrow.triangle.branch" }
        return "exclamationmark.triangle.fill"
    }

    private func decisionColor(_ decision: ConflictDecision) -> Color {
        dispositionColor(decision.disposition)
    }

    private func dispositionColor(_ disposition: DecisionDisposition) -> Color {
        switch disposition {
        case .unresolved: .red
        case .resolved: .blue
        case .expected: .green
        }
    }

    private var sampleView: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Sample input").font(.headline)
                    Spacer()
                    if document != nil {
                        Picker("Sample", selection: selectedSampleBinding) {
                            ForEach(document?.wrappedValue.samples ?? []) { sample in
                                Text(sample.name).tag(sample.id)
                            }
                        }
                        .labelsHidden().frame(maxWidth: 180)
                        Button("Add Sample", systemImage: "plus", action: addSample).labelStyle(.iconOnly)
                        Button("Delete Sample", systemImage: "minus", action: deleteSelectedSample)
                            .labelStyle(.iconOnly)
                        .disabled((document?.wrappedValue.samples.count ?? 0) <= 1)
                    }
                }
                if document != nil {
                    TextField("Sample name", text: selectedSampleNameBinding)
                        .textFieldStyle(.plain)
                        .font(.subheadline.bold())
                }
                HStack {
                    TextField(store.lexerResult == nil ? "Whitespace-separated terminal tokens" : "Raw source text", text: sampleInputBinding)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit { store.parseSample() }
                    Button("Parse", systemImage: "play.fill") { store.parseSample() }
                }
                Label(
                    store.runtimeResult.diagnostics.isEmpty
                        ? store.runtimeResult.outcome.label
                        : "\(store.runtimeResult.outcome.label) with \(store.runtimeResult.diagnostics.count) diagnostic(s)",
                    systemImage: outcomeIcon
                )
                    .foregroundStyle(outcomeColor)
                if case .rejected(_, let expected) = store.runtimeResult.outcome, !expected.isEmpty {
                    Text("Expected: \(expected.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let lexer = store.lexerResult {
                    Text("Lexer tokens").font(.headline)
                    if lexer.tokens.isEmpty {
                        Text(lexer.hasErrors ? "No tokens emitted." : "Empty token stream.").foregroundStyle(.secondary)
                    } else {
                        Table(lexer.tokens) {
                            TableColumn("Token") { Text($0.kind).font(.system(.body, design: .monospaced)) }
                            TableColumn("Lexeme") { Text($0.lexeme).font(.system(.body, design: .monospaced)) }
                            TableColumn("Mode") { Text($0.mode).font(.system(.body, design: .monospaced)) }
                            TableColumn("Location") { Text("\($0.range.start.line):\($0.range.start.column)") }
                        }.frame(minHeight: 100, maxHeight: 180)
                    }
                    ForEach(lexer.diagnostics) { diagnostic in
                        Label("\(diagnostic.range.start.line):\(diagnostic.range.start.column) [\(diagnostic.mode)] \(diagnostic.message)", systemImage: "xmark.octagon.fill")
                            .font(.caption).foregroundStyle(.red)
                    }
                }
                if !store.runtimeResult.diagnostics.isEmpty {
                    Text("Syntax diagnostics").font(.headline)
                    ForEach(store.runtimeResult.diagnostics, id: \.index) { diagnostic in
                        VStack(alignment: .leading, spacing: 3) {
                            Button {
                                presentDetail(.state(diagnostic.state))
                            } label: {
                                Label(diagnostic.message, systemImage: "exclamationmark.triangle.fill")
                            }
                            .buttonStyle(.link)
                            Text("Expected: \(diagnostic.expected.joined(separator: ", "))")
                            if let detail = diagnostic.recoveryDetail {
                                Text(detail).foregroundStyle(.orange)
                            }
                        }
                        .font(.caption)
                    }
                }
                Divider()
                Text("Parse tree").font(.headline)
                ScrollView {
                    Text(store.runtimeResult.tree?.rendered() ?? "No accepted parse tree.")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 160, maxHeight: .infinity, alignment: .top)
            }
            .padding()
            .frame(
                minWidth: 260, idealWidth: 420, maxWidth: .infinity,
                maxHeight: .infinity, alignment: .topLeading
            )
            .layoutPriority(1)
            VStack(spacing: 0) {
                Picker("Parser visualization", selection: $sampleVisualization) {
                    ForEach(SampleVisualization.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(8)
                Divider()
                if sampleVisualization == .animated, let timeline = store.parserVisualizationTimeline {
                    GrammarParserVisualizationView(timeline: timeline)
                        .accessibilityIdentifier("interactive-parser-visualization")
                } else {
                    replayView(frames: store.runtimeResult.frames)
                }
            }
            .frame(
                minWidth: 260, idealWidth: 420, maxWidth: .infinity,
                maxHeight: .infinity, alignment: .topLeading
            )
            .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var testsView: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Test suite").font(.headline)
                    Spacer()
                    Button("Add Test", systemImage: "plus", action: addTest).labelStyle(.iconOnly)
                    Button("Delete Test", systemImage: "minus", action: deleteSelectedTest)
                        .labelStyle(.iconOnly).disabled(selectedTestID == nil)
                }
                Button("Run All", systemImage: "play.fill") {
                    store.runTests(document?.wrappedValue.tests ?? [])
                }
                .disabled(document?.wrappedValue.tests.isEmpty != false || store.frontEnd.hasErrors)
                if let report = store.testReport {
                    Label(
                        "\(report.passed) passed · \(report.failed) failed",
                        systemImage: report.allPassed ? "checkmark.seal.fill" : "xmark.octagon.fill"
                    )
                    .foregroundStyle(report.allPassed ? .green : .red)
                }
                List(selection: $selectedTestID) {
                    ForEach(document?.wrappedValue.tests ?? []) { test in
                        HStack {
                            Image(systemName: testStatusIcon(test.id))
                                .foregroundStyle(testStatusColor(test.id))
                            VStack(alignment: .leading) {
                                Text(test.name)
                                Text(test.expectation.rawValue).font(.caption).foregroundStyle(.secondary)
                            }
                        }.tag(test.id)
                    }
                }
            }
            .padding().frame(minWidth: 260, idealWidth: 300)

            if let test = selectedTest {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Test name", text: testNameBinding).font(.title3.bold())
                        Picker("Expected outcome", selection: testExpectationBinding) {
                            ForEach(WorkbenchTestExpectation.allCases) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented)
                        Text("Input").font(.headline)
                        TextEditor(text: testInputBinding)
                            .font(.system(.body, design: .monospaced)).frame(minHeight: 70)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.3)))
                        Text("Expected tree snapshot (optional)").font(.headline)
                        TextEditor(text: testTreeBinding)
                            .font(.system(.caption, design: .monospaced)).frame(minHeight: 100)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.3)))
                        if let result = store.testReport?.results.first(where: { $0.id == test.id }) {
                            Divider()
                            Label(result.status.rawValue.capitalized, systemImage: testStatusIcon(test.id))
                                .font(.headline).foregroundStyle(testStatusColor(test.id))
                            LabeledContent("Actual", value: result.actual)
                            Text(result.message).foregroundStyle(.secondary)
                            LabeledContent("Tokens", value: result.tokens.joined(separator: " "))
                            Text("Actual tree").font(.headline)
                            Text(result.tree ?? "No parse tree.")
                                .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        }
                    }.padding().frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView("Select a test", systemImage: "checklist")
            }
        }
        .onAppear {
            if selectedTestID == nil { selectedTestID = document?.wrappedValue.tests.first?.id }
        }
    }

    private var researchView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Selected research preview").font(.title2.bold())
                Text("Explore a small research question with declared expectations, repeatable evidence, and a plain-language conclusion.")
                    .foregroundStyle(.secondary)
                Picker("Research question", selection: Binding(
                    get: { store.selectedResearchStudyID },
                    set: { store.selectResearchStudy($0) }
                )) {
                    ForEach(GrammarSelectedResearchCatalog.studies) { study in
                        Text(study.title).tag(study.id)
                    }
                }
                .pickerStyle(.menu)
                if let study = GrammarSelectedResearchCatalog.study(id: store.selectedResearchStudyID) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(study.question).font(.headline)
                            Text(study.context).foregroundStyle(.secondary)
                            HStack {
                                Button("Run selected preview", systemImage: "checkmark.seal") {
                                    store.runSelectedResearchPreview()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(store.isRunningSelectedResearch)
                                if store.isRunningSelectedResearch { ProgressView().controlSize(.small) }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let error = store.selectedResearchError {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
                if let preview = store.selectedResearchPreview {
                    selectedResearchPreviewView(preview)
                }
                Divider().padding(.vertical, 4)
                Text("Generalized LR exploration").font(.title2.bold())
                Text("Merges equivalent parser configurations into a shared-packed forest, then materializes only the requested concrete alternatives. Explicit limits bound exploration and forest growth.")
                    .foregroundStyle(.secondary)
                Toggle("Explore alternatives suppressed by precedence and associativity", isOn: $exploresResolvedConflicts)
                HStack {
                    Button("Explore sample", systemImage: "point.3.connected.trianglepath.dotted") {
                        store.exploreAmbiguity(includingResolvedConflicts: exploresResolvedConflicts)
                    }
                    .disabled(store.isExploringGeneralizedParse)
                    if store.isExploringGeneralizedParse { ProgressView().controlSize(.small) }
                    Text(store.sampleInput).font(.system(.caption, design: .monospaced))
                        .lineLimit(1).foregroundStyle(.secondary)
                }
                if let result = store.generalizedResult {
                    Divider()
                    Label(
                        researchStatus(result),
                        systemImage: result.isAmbiguous ? "square.stack.3d.up.fill" : "checkmark.circle.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(result.isAmbiguous ? .orange : (result.isAccepted ? .green : .red))
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                        GridRow { Text("Explored configurations"); Text("\(result.metrics.exploredConfigurations)") }
                        GridRow { Text("Peak pending"); Text("\(result.metrics.peakPendingConfigurations)") }
                        GridRow { Text("Branch points"); Text("\(result.metrics.branchPoints)") }
                        GridRow { Text("Duplicate configurations"); Text("\(result.metrics.duplicateConfigurations)") }
                        GridRow { Text("Discarded configurations"); Text("\(result.metrics.discardedConfigurations)") }
                        GridRow { Text("Shift / reduce actions"); Text("\(result.metrics.shiftActions) / \(result.metrics.reductionActions)") }
                        GridRow { Text("Shared forest nodes"); Text("\(result.sharedForest.nodes.count)") }
                        GridRow { Text("Packed families"); Text("\(result.sharedForest.packedFamilyCount)") }
                        GridRow { Text("Ambiguous nodes"); Text("\(result.sharedForest.ambiguousNodeCount)") }
                        GridRow { Text("Represented derivations"); Text("\(result.sharedForest.derivationCount(upTo: 1_000_000))\(result.sharedForest.derivationCount(upTo: 1_000_001) > 1_000_000 ? "+" : "")") }
                        GridRow { Text("Furthest token"); Text("\(result.metrics.furthestTokenIndex)") }
                    }
                    .font(.caption.monospacedDigit())
                    if !result.reachedLimits.isEmpty {
                        LabeledContent(
                            "Reached limits",
                            value: result.reachedLimits.map(\.rawValue).sorted().joined(separator: ", ")
                        ).font(.caption)
                    }
                    if let diagnostic = result.syntaxDiagnostics.first {
                        Text(diagnostic.message).foregroundStyle(.red)
                    }
                    ForEach(Array(result.forest.alternatives.enumerated()), id: \.element.id) { index, alternative in
                        DisclosureGroup("Alternative \(index + 1)") {
                            Text(alternative.tree.rendered())
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 5)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No research result", systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text("Enter input in Sample, then explore its parse alternatives here.")
                    )
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func selectedResearchPreviewView(_ preview: GrammarSelectedResearchPreview) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    preview.passed ? "Selected evidence supports the hypothesis" : "The hypothesis was falsified",
                    systemImage: preview.passed ? "checkmark.seal.fill" : "xmark.seal.fill"
                )
                .font(.headline)
                .foregroundStyle(preview.passed ? .green : .red)
                Text(preview.conclusion)
                ForEach(preview.observations) { observation in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: observation.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(observation.passed ? .green : .red)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(observation.title).font(.headline)
                                Spacer()
                                Text(observation.value).foregroundStyle(.secondary)
                            }
                            Text(observation.explanation).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                DisclosureGroup("Inspect evidence and limitations") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Programme", value: preview.report.programmeFingerprint)
                        LabeledContent("Evidence", value: preview.report.evidenceFingerprint)
                        LabeledContent("Cases", value: "\(preview.report.passedCases)/\(preview.report.cases.count) passed")
                        ForEach(preview.limitations, id: \.self) { limitation in
                            Label(limitation, systemImage: "info.circle")
                        }
                    }
                    .font(.caption)
                    .textSelection(.enabled)
                    .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func researchStatus(_ result: GrammarGeneralizedParseResult) -> String {
        switch result.status {
        case .accepted: "One accepted parse"
        case .ambiguous: "\(result.alternatives.count) accepted alternatives"
        case .truncated: "Bound reached after finding \(result.alternatives.count) alternative(s)"
        case .rejected: "No accepted alternatives"
        case .invalidGrammar: "Grammar is invalid"
        case .lexicalError: "Input has lexical errors"
        case .cancelled: "Exploration was cancelled"
        }
    }

    private var selectedTest: WorkbenchTestCase? {
        guard let selectedTestID else { return nil }
        return document?.wrappedValue.tests.first { $0.id == selectedTestID }
    }

    private func updateSelectedTest(_ update: (inout WorkbenchTestCase) -> Void) {
        guard let document, let selectedTestID else { return }
        var updated = document.wrappedValue
        guard let index = updated.tests.firstIndex(where: { $0.id == selectedTestID }) else { return }
        update(&updated.tests[index])
        document.wrappedValue = updated
        store.clearTestReport()
    }

    private var testNameBinding: Binding<String> {
        .init(get: { selectedTest?.name ?? "" }, set: { value in updateSelectedTest { $0.name = value } })
    }

    private var testInputBinding: Binding<String> {
        .init(get: { selectedTest?.input ?? "" }, set: { value in updateSelectedTest { $0.input = value } })
    }

    private var testExpectationBinding: Binding<WorkbenchTestExpectation> {
        .init(get: { selectedTest?.expectation ?? .accept }, set: { value in updateSelectedTest { $0.expectation = value } })
    }

    private var testTreeBinding: Binding<String> {
        .init(get: { selectedTest?.expectedTree ?? "" }, set: { value in
            updateSelectedTest { $0.expectedTree = value.isEmpty ? nil : value }
        })
    }

    private func testStatusIcon(_ id: UUID) -> String {
        switch store.testReport?.results.first(where: { $0.id == id })?.status {
        case .passed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .invalid: "exclamationmark.triangle.fill"
        case nil: "circle"
        }
    }

    private func testStatusColor(_ id: UUID) -> Color {
        switch store.testReport?.results.first(where: { $0.id == id })?.status {
        case .passed: .green
        case .failed: .red
        case .invalid: .orange
        case nil: .secondary
        }
    }

    private var outcomeIcon: String {
        switch store.runtimeResult.outcome {
        case .accepted: store.runtimeResult.diagnostics.isEmpty ? "checkmark.circle.fill" : "checkmark.circle.badge.exclamationmark.fill"
        case .rejected: "xmark.octagon.fill"
        case .conflict: "arrow.triangle.branch"
        case .looping: "repeat.circle.fill"
        }
    }

    private var outcomeColor: Color {
        switch store.runtimeResult.outcome {
        case .accepted: store.runtimeResult.diagnostics.isEmpty ? .green : .orange
        case .rejected: .red
        case .conflict: .orange
        case .looping: .purple
        }
    }

    private var detailIsPresented: Binding<Bool> {
        .init(
            get: { presentedDetail != nil },
            set: { if !$0 { presentedDetail = nil } }
        )
    }

    @ViewBuilder private var contextualDetail: some View {
        if let selection = presentedDetail {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) { inspectorContent(selection) }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func presentDetail(_ selection: ArtifactIdentity) {
        store.select(selection)
        presentedDetail = selection
    }

    @ViewBuilder private func inspectorContent(_ selection: ArtifactIdentity) -> some View {
        switch selection {
        case .state(let id):
            Text(id.description).font(.title2.bold())
            if let summary = store.artifact.decisionSummary(for: id) {
                Label("\(summary.disposition.label) · \(summary.decisions.count) decision\(summary.decisions.count == 1 ? "" : "s")", systemImage: decisionIcon(summary.decisions[0]))
                    .foregroundStyle(dispositionColor(summary.disposition))
                ForEach(summary.decisions) { decision in
                    Button("\(decision.cell.symbol): \(store.artifact.candidateActions(for: decision).map(\.label).joined(separator: " / "))") {
                        presentDetail(.decision(decision.id))
                    }.buttonStyle(.link)
                }
            }
            ForEach(store.artifact.state(id)?.items ?? []) { item in
                Button(item.text) { presentDetail(.production(item.production)) }.buttonStyle(.plain).font(.system(.body, design: .monospaced))
            }
            Text("Outgoing transitions").font(.headline)
            ForEach(store.artifact.transitions.filter { $0.from == id }) { transition in
                Button("\(transition.symbol) → \(transition.to)") { presentDetail(.state(transition.to)) }.buttonStyle(.link)
            }
        case .production(let id):
            Text("Production \(id.rawValue)").font(.title2.bold())
            Text(store.artifact.productions.first(where: { $0.id == id })?.text ?? "Unavailable").font(.system(.body, design: .monospaced))
        case .cell(let id):
            Text("\(id.state) / \(id.symbol)").font(.title2.bold())
            Text(store.artifact.cell(id)?.actions.map(\.label).joined(separator: " or ") ?? "Empty")
        case .decision(let id):
            if let decision = store.artifact.decision(id) {
                Label(decision.title, systemImage: "point.3.connected.trianglepath.dotted").font(.title3.bold())
                Label(decision.disposition.label, systemImage: decisionIcon(decision))
                    .foregroundStyle(dispositionColor(decision.disposition))
                Text(decision.explanation)
                if decision.isExpected {
                    Label("Suppressed by matching %expect", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                }
                if let provenance = decision.provenance {
                    provenanceView(provenance)
                }
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                    GridRow {
                        Text("Candidate actions").foregroundStyle(.secondary)
                        Text(store.artifact.candidateActions(for: decision).map(\.label).joined(separator: " / "))
                    }
                    GridRow {
                        Text("Effective action").foregroundStyle(.secondary)
                        Text(store.artifact.cell(decision.cell)?.actions.map(\.label).joined(separator: " / ") ?? "error")
                    }
                }.font(.caption)
                conflictGraphic(decision)
                Text("\(decision.disposition == .resolved ? "Decision trigger" : "Minimal counterexample"): \(decision.witness.joined(separator: " "))")
                    .font(.system(.body, design: .monospaced))
                if !decision.branchAnalyses.isEmpty {
                    branchTrees(decision.branchAnalyses)
                }
                Picker("Branch", selection: $store.selectedBranch) { ForEach(decision.branches.indices, id: \.self) { Text("Branch \($0 + 1)").tag($0) } }.pickerStyle(.segmented)
                replayView(frames: decision.branches[min(store.selectedBranch, decision.branches.count - 1)])
            }
        case .traceStep(let index): Text("Trace step \(index)")
        }
    }

    private func provenanceView(_ provenance: ConflictProvenance) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
            GridRow { Text("Resolution").foregroundStyle(.secondary); Text(provenance.kind.rawValue) }
            GridRow { Text("Lookahead").foregroundStyle(.secondary); Text("‘\(provenance.lookahead)’ · level \(provenance.lookaheadLevel.map(String.init) ?? "none")") }
            if let production = provenance.production {
                GridRow {
                    Text("Production").foregroundStyle(.secondary)
                    Text("\(production.rawValue) via \(provenance.productionSymbol ?? "no precedence symbol") · level \(provenance.productionLevel.map(String.init) ?? "none")")
                }
            }
            if let associativity = provenance.associativity {
                GridRow { Text("Associativity").foregroundStyle(.secondary); Text(associativity.rawValue) }
            }
            if let selected = provenance.selectedAction {
                GridRow { Text("Selected action").foregroundStyle(.secondary); Text(selected.label) }
            }
        }
        .font(.caption)
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func branchTrees(_ analyses: [ConflictBranchAnalysis]) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(analyses) { analysis in
                VStack(alignment: .leading, spacing: 6) {
                    Text(analysis.action.label).font(.headline)
                    Text(analysis.outcome).font(.caption).foregroundStyle(.secondary)
                    ScrollView([.horizontal, .vertical]) {
                        Text(analysis.tree ?? "No accepting tree.")
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 100, maxHeight: 220)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.35)))
            }
        }
    }

    private func conflictGraphic(_ decision: ConflictDecision) -> some View {
        VStack(spacing: 8) {
            Text(decision.cell.state.description).padding(8).background(.blue.opacity(0.2)).clipShape(Capsule())
            HStack {
                ForEach(decision.branches.indices, id: \.self) { index in
                    Text(store.artifact.candidateActions(for: decision)[safe: index]?.label ?? "Branch \(index + 1)")
                        .frame(maxWidth: .infinity).padding(8)
                        .background(index == 0 ? .green.opacity(0.2) : .orange.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }.padding().overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.3)))
    }

    private func replayView(frames: [ReplayFrame]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Replay").font(.headline)
            Slider(
                value: Binding(
                    get: { Double(min(store.replayIndex, max(0, frames.count - 1))) },
                    set: {
                        let index = Int($0)
                        if frames.indices.contains(index) {
                            store.selectReplayFrame(frames[index], index: index)
                        }
                    }
                ),
                in: 0...Double(max(1, frames.count - 1)),
                step: 1
            )
            if !frames.isEmpty {
                let frame = frames[min(store.replayIndex, frames.count - 1)]
                LabeledContent("Stack", value: frame.stack.joined(separator: " "))
                LabeledContent("Input", value: frame.remainingInput.joined(separator: " "))
                LabeledContent("Action", value: frame.action)
                HStack {
                    if let state = frame.state { Button("State \(state)") { presentDetail(.state(state)) }.buttonStyle(.link) }
                    if let cell = frame.cell { Button("Cell \(cell.symbol)") { presentDetail(.cell(cell)) }.buttonStyle(.link) }
                    if let production = frame.production { Button("Production \(production.rawValue)") { presentDetail(.production(production)) }.buttonStyle(.link) }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func exportHTML() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.html]; panel.nameFieldStringValue = "grammar-artifact.html"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try HTMLExporter.render(store.artifact, runtime: store.runtimeResult, lexer: store.lexerResult, testReport: store.testReport, algorithmComparison: store.algorithmComparison).write(to: url, atomically: true, encoding: .utf8); exportMessage = "Exported to \(url.lastPathComponent)." }
        catch { exportMessage = "Could not export: \(error.localizedDescription)" }
    }

    private func exportInterchange() {
        guard let document else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "grammar-workbench.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try GrammarInterchangeCodec.encode(document.wrappedValue).write(to: url, options: .atomic)
            exportMessage = "Exported project interchange to \(url.lastPathComponent)."
        } catch {
            exportMessage = "Could not export interchange: \(error.localizedDescription)"
        }
    }

    private func importInterchange() {
        guard let document else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try GrammarInterchangeCodec.decode(Data(contentsOf: url))
            document.wrappedValue = imported
            store.notation = imported.notation
            store.load(source: imported.source, documentName: url.lastPathComponent)
            store.algorithm = LRAlgorithm(rawValue: imported.algorithm) ?? .lalr
            store.sampleInput = imported.samples.first { $0.id == imported.selectedSampleID }?.input ?? ""
            store.parseSample()
            selectedTestID = imported.tests.first?.id
            tab = .tests
            exportMessage = "Imported \(url.lastPathComponent)."
        } catch {
            exportMessage = "Could not import interchange: \(error.localizedDescription)"
        }
    }

    private func exportArtifactInterchange() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "grammar-artifact.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try GrammarInterchangeCodec.encodeArtifact(
                source: sourceBinding.wrappedValue,
                algorithm: store.algorithm.rawValue,
                notation: store.notation
            )
            try data.write(to: url, options: .atomic)
            exportMessage = "Exported artifact interchange to \(url.lastPathComponent)."
        } catch {
            exportMessage = "Could not export artifact interchange: \(error.localizedDescription)"
        }
    }

    private func exportSwiftParser() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.sourceCode]
        panel.nameFieldStringValue = "GeneratedParser.swift"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let algorithm = GrammarAlgorithm(rawValue: store.algorithm.rawValue) else {
                throw GrammarInterchangeError.invalidAlgorithm(store.algorithm.rawValue)
            }
            let compilation = GrammarWorkbenchAPI.compile(.init(
                source: sourceBinding.wrappedValue, algorithm: algorithm, notation: store.notation
            ))
            let source = try compilation.generateSwiftParser()
            try source.write(to: url, atomically: true, encoding: .utf8)
            exportMessage = "Generated Swift parser at \(url.lastPathComponent)."
        } catch {
            exportMessage = "Could not generate parser: \(error.localizedDescription)"
        }
    }

    private func exportSemanticModel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Grammar.semantic.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let algorithm = GrammarAlgorithm(rawValue: store.algorithm.rawValue) else {
                throw GrammarInterchangeError.invalidAlgorithm(store.algorithm.rawValue)
            }
            let compilation = GrammarWorkbenchAPI.compile(.init(
                source: sourceBinding.wrappedValue, algorithm: algorithm, notation: store.notation
            ))
            let result = try SemanticModelJSONGrammarGenerator().generate(
                from: compilation, options: .init()
            )
            guard let file = result.files.first else {
                throw GrammarGeneratorRegistryError.emptyResult("semantic-model-json")
            }
            try file.contents.write(to: url, options: .atomic)
            exportMessage = "Exported semantic model to \(url.lastPathComponent)."
        } catch {
            exportMessage = "Could not export semantic model: \(error.localizedDescription)"
        }
    }

    private func exportSemanticSwift() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.sourceCode]
        panel.nameFieldStringValue = "GrammarSemantics.swift"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let algorithm = GrammarAlgorithm(rawValue: store.algorithm.rawValue) else {
                throw GrammarInterchangeError.invalidAlgorithm(store.algorithm.rawValue)
            }
            let compilation = GrammarWorkbenchAPI.compile(.init(
                source: sourceBinding.wrappedValue, algorithm: algorithm, notation: store.notation
            ))
            let result = try SwiftSemanticActionsGrammarGenerator().generate(
                from: compilation, options: .init()
            )
            guard let file = result.files.first else {
                throw GrammarGeneratorRegistryError.emptyResult("semantic-swift")
            }
            try file.contents.write(to: url, options: .atomic)
            exportMessage = "Generated semantic actions at \(url.lastPathComponent)."
        } catch {
            exportMessage = "Could not generate semantic actions: \(error.localizedDescription)"
        }
    }

    private func exportBNF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "grammar.bnf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let algorithm = GrammarAlgorithm(rawValue: store.algorithm.rawValue) else {
                throw GrammarInterchangeError.invalidAlgorithm(store.algorithm.rawValue)
            }
            let compilation = GrammarWorkbenchAPI.compile(.init(
                source: sourceBinding.wrappedValue, algorithm: algorithm, notation: store.notation
            ))
            let result = try BNFGrammarGenerator().generate(from: compilation, options: .init())
            guard let file = result.files.first else {
                throw GrammarGeneratorRegistryError.emptyResult("bnf")
            }
            try file.contents.write(to: url, options: .atomic)
            exportMessage = "Generated portable BNF at \(url.lastPathComponent)."
        } catch {
            exportMessage = "Could not generate BNF: \(error.localizedDescription)"
        }
    }

    private func openGrammar() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let source = try String(contentsOf: url, encoding: .utf8)
            let notation = GrammarSourceNotationDetector.detect(
                source: source, pathExtension: url.pathExtension
            )
            notationBinding.wrappedValue = notation
            store.load(source: source, documentName: url.lastPathComponent)
            tab = .analysis
        } catch {
            exportMessage = "Could not open \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func openSourceProject() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        panel.message = "Choose a Grammar Workbench source-project descriptor."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isLoadingSourceProject = true
        Task {
            do {
                let loaded = try await Task.detached {
                    try GrammarSourceProjectLoader.load(at: url)
                }.value
                let workspace = try GrammarProjectWorkspace(manifest: loaded.manifest)
                let analysis = try await workspace.analyze()
                let semantics: GrammarSemanticWorkspaceSnapshot? = if let schema = loaded.semanticSchema {
                    analysis.semanticWorkspace(schema: schema)
                } else {
                    nil
                }
                loadedSourceProject = loaded
                sourceProjectAnalysis = analysis
                sourceProjectSemantics = semantics
                selectedSourceProjectDocumentID = loaded.manifest.sources.first?.id
                let grammar = loaded.manifest.grammar
                if let document {
                    var updated = document.wrappedValue
                    updated.source = grammar.source
                    updated.notation = grammar.notation
                    updated.algorithm = grammar.algorithm.rawValue
                    document.wrappedValue = updated
                }
                store.notation = grammar.notation
                store.algorithm = LRAlgorithm(rawValue: grammar.algorithm.rawValue) ?? .lalr
                store.load(source: grammar.source, documentName: loaded.descriptor.name)
                tab = .project
            } catch {
                exportMessage = "Could not open source project: \(error.localizedDescription)"
            }
            isLoadingSourceProject = false
        }
    }

    private var sourceBinding: Binding<String> {
        guard let document else { return .constant(store.artifact.grammarSource) }
        return Binding(
            get: { document.wrappedValue.source },
            set: { value in
                var updated = document.wrappedValue
                updated.source = value
                document.wrappedValue = updated
                store.updateSource(value)
            }
        )
    }

    private var algorithmBinding: Binding<LRAlgorithm> {
        Binding(
            get: { store.algorithm },
            set: { value in
                store.algorithm = value
                guard let document else { return }
                var updated = document.wrappedValue
                updated.algorithm = value.rawValue
                document.wrappedValue = updated
            }
        )
    }

    private var notationBinding: Binding<GrammarSourceNotation> {
        Binding(
            get: { store.notation },
            set: { value in
                store.notation = value
                guard let document else { return }
                var updated = document.wrappedValue
                updated.notation = value
                document.wrappedValue = updated
            }
        )
    }

    private var selectedSampleBinding: Binding<UUID> {
        Binding(
            get: {
                document?.wrappedValue.selectedSampleID
                    ?? document?.wrappedValue.samples.first?.id
                    ?? UUID()
            },
            set: { id in
                guard let document else { return }
                var updated = document.wrappedValue
                updated.selectedSampleID = id
                document.wrappedValue = updated
                store.sampleInput = updated.samples.first { $0.id == id }?.input ?? ""
                store.parseSample()
            }
        )
    }

    private var sampleInputBinding: Binding<String> {
        Binding(
            get: { store.sampleInput },
            set: { value in
                store.sampleInput = value
                guard let document else { return }
                var updated = document.wrappedValue
                if let index = updated.samples.firstIndex(where: { $0.id == updated.selectedSampleID }) {
                    updated.samples[index].input = value
                    document.wrappedValue = updated
                }
            }
        )
    }

    private var selectedSampleNameBinding: Binding<String> {
        Binding(
            get: {
                guard let document else { return "" }
                return document.wrappedValue.samples.first {
                    $0.id == document.wrappedValue.selectedSampleID
                }?.name ?? ""
            },
            set: { value in
                guard let document else { return }
                var updated = document.wrappedValue
                if let index = updated.samples.firstIndex(where: { $0.id == updated.selectedSampleID }) {
                    updated.samples[index].name = value
                    document.wrappedValue = updated
                }
            }
        )
    }

    private func addSample() {
        guard let document else { return }
        var updated = document.wrappedValue
        let sample = WorkbenchSample(name: "Sample \(updated.samples.count + 1)", input: "")
        updated.samples.append(sample)
        updated.selectedSampleID = sample.id
        document.wrappedValue = updated
        store.sampleInput = ""
        store.parseSample()
    }

    private func addTest() {
        guard let document else { return }
        var updated = document.wrappedValue
        let test = WorkbenchTestCase(name: "Test \(updated.tests.count + 1)", input: "", expectation: .accept)
        updated.tests.append(test)
        document.wrappedValue = updated
        selectedTestID = test.id
        store.clearTestReport()
    }

    private func deleteSelectedTest() {
        guard let document, let selectedTestID else { return }
        var updated = document.wrappedValue
        guard let index = updated.tests.firstIndex(where: { $0.id == selectedTestID }) else { return }
        updated.tests.remove(at: index)
        document.wrappedValue = updated
        self.selectedTestID = updated.tests.isEmpty ? nil : updated.tests[min(index, updated.tests.count - 1)].id
        store.clearTestReport()
    }

    private func deleteSelectedSample() {
        guard let document else { return }
        var updated = document.wrappedValue
        guard updated.samples.count > 1,
              let index = updated.samples.firstIndex(where: { $0.id == updated.selectedSampleID }) else { return }
        updated.samples.remove(at: index)
        updated.selectedSampleID = updated.samples[min(index, updated.samples.count - 1)].id
        document.wrappedValue = updated
        store.sampleInput = updated.samples.first { $0.id == updated.selectedSampleID }?.input ?? ""
        store.parseSample()
    }

    private func applyQuickFix(_ fix: GrammarQuickFix) {
        let updated = fix.applying(to: sourceBinding.wrappedValue)
        sourceBinding.wrappedValue = updated
    }
}
#endif

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
