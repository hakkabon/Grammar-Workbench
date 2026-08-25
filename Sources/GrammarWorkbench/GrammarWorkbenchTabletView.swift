#if os(iOS)
import GrammarDiagramKit
import SwiftUI

private enum TabletDestination: String, CaseIterable, Identifiable {
    case guide = "Guide"
    case analysis = "Analysis"
    case sample = "Sample"
    case tests = "Tests"
    case visuals = "Visuals"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .guide: "house"
        case .analysis: "waveform.path.ecg"
        case .sample: "play.rectangle"
        case .tests: "checkmark.circle"
        case .visuals: "point.topleft.down.to.point.bottomright.curvepath"
        }
    }
}

/// The first touch-first shell for large iPads. It intentionally concentrates
/// on grammar authoring and exploration while the dense expert workspaces stay
/// in the macOS application.
public struct GrammarWorkbenchTabletView: View {
    @Binding private var document: GrammarWorkbenchDocument
    private let documentName: String

    @State private var store: ExplorerStore
    @State private var destination: TabletDestination? = .guide
    @State private var replSession: GrammarREPLSession
    @State private var replCommand = ""
    @State private var testReport: WorkbenchTestReport?
    @State private var showsSourceEditor = false

    public init(document: Binding<GrammarWorkbenchDocument>, documentName: String) {
        self._document = document
        self.documentName = documentName
        let value = document.wrappedValue
        _store = State(initialValue: ExplorerStore(
            source: value.source,
            algorithm: LRAlgorithm(rawValue: value.algorithm) ?? .lalr,
            notation: value.notation,
            sampleInput: value.samples.first(where: { $0.id == value.selectedSampleID })?.input ?? "",
            documentName: documentName
        ))
        _replSession = State(initialValue: GrammarREPLSession(compilation: GrammarWorkbenchAPI.compile(.init(
            source: value.source,
            algorithm: GrammarAlgorithm(rawValue: value.algorithm) ?? .lalr,
            notation: value.notation
        ))))
    }

    public var body: some View {
        NavigationSplitView {
            List(TabletDestination.allCases, selection: $destination) { item in
                Label(item.rawValue, systemImage: item.systemImage).tag(item)
            }
            .navigationTitle("Grammar Workbench")
        } detail: {
            GeometryReader { proxy in
                if proxy.size.width >= WorkbenchVisualFoundation.tabletComfortableWidth {
                    HStack(spacing: 0) {
                        sourcePane.frame(minWidth: WorkbenchVisualFoundation.tabletEditorMinimumWidth)
                        Divider()
                        workspace.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    workspace
                }
            }
            .navigationTitle(destination?.rawValue ?? "Grammar Workbench")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Source", systemImage: "doc.text") { showsSourceEditor = true }
                        .keyboardShortcut("e", modifiers: .command)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu(store.algorithm.rawValue) {
                        ForEach(LRAlgorithm.allCases) { algorithm in
                            Button(algorithm.rawValue) { setAlgorithm(algorithm) }
                        }
                    }
                }
            }
            .sheet(isPresented: $showsSourceEditor) {
                NavigationStack {
                    sourcePane
                        .navigationTitle("Grammar source")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showsSourceEditor = false }
                            }
                        }
                }
            }
        }
    }

    private var sourcePane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label(documentName, systemImage: "doc.text").font(.headline).lineLimit(1)
                Spacer()
                Text(store.notation.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }
            .padding()
            Divider()
            TextEditor(text: sourceBinding)
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(6)
                .contextMenu {
                    Menu("Interpret Grammar As") {
                        ForEach(GrammarSourceNotation.allCases) { notation in
                            Button(notation.displayName) { setNotation(notation) }
                        }
                    }
                }
            if !store.frontEnd.diagnostics.isEmpty {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(store.frontEnd.diagnostics) { diagnostic in
                            Label(
                                "\(diagnostic.range.start.line):\(diagnostic.range.start.column)  \(diagnostic.message)",
                                systemImage: diagnostic.severity == .error
                                    ? "xmark.octagon.fill" : "exclamationmark.triangle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(diagnostic.severity == .error ? .red : .orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding()
                }
                .frame(maxHeight: 150)
            }
        }
    }

    @ViewBuilder private var workspace: some View {
        switch destination ?? .guide {
        case .guide: guide
        case .analysis: analysis
        case .sample: sample
        case .tests: tests
        case .visuals: visuals
        }
    }

    private var guide: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("Large-iPad preview", systemImage: "ipad.landscape").font(.title2.bold())
                Text("Edit the grammar beside its analysis on a large display. In narrower Split View sizes, use the navigation sidebar to move between focused workspaces.")
                GroupBox("Start here") {
                    VStack(alignment: .leading, spacing: 12) {
                        guideButton("Inspect grammar health", destination: .analysis, icon: "waveform.path.ecg")
                        guideButton("Try an input", destination: .sample, icon: "play.rectangle")
                        guideButton("Run saved tests", destination: .tests, icon: "checkmark.circle")
                        guideButton("Explore a railroad diagram", destination: .visuals, icon: "point.topleft.down.to.point.bottomright.curvepath")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(24).frame(maxWidth: 720, alignment: .leading)
        }
    }

    private func guideButton(_ title: String, destination value: TabletDestination, icon: String) -> some View {
        Button { destination = value } label: { Label(title, systemImage: icon) }
    }

    private var analysis: some View {
        List {
            Section("Grammar") {
                LabeledContent("Productions", value: "\(store.artifact.productions.count)")
                LabeledContent("Terminals", value: "\(store.artifact.terminals.count)")
                LabeledContent("Nonterminals", value: "\(store.artifact.nonterminals.count)")
            }
            Section("LR construction") {
                LabeledContent("Algorithm", value: store.algorithm.rawValue)
                LabeledContent("States", value: "\(store.artifact.states.count)")
                LabeledContent("Table entries", value: "\(store.artifact.cells.count)")
                LabeledContent("Decisions", value: "\(store.artifact.decisions.count)")
            }
            Section("Productions") {
                ForEach(store.artifact.productions, id: \.id) { production in
                    Text(production.text).font(.system(.body, design: .monospaced))
                }
            }
        }
    }

    private var sample: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sample input").font(.headline)
            TextEditor(text: sampleBinding)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120, maxHeight: 220)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
            Label(store.runtimeResult.outcome.label, systemImage: sampleOutcomeIcon)
                .foregroundStyle(sampleOutcomeColor)
            if let tree = store.runtimeResult.tree {
                ScrollView([.horizontal, .vertical]) {
                    Text(tree.rendered()).font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer()
        }.padding(24)
    }

    private var sampleOutcomeIcon: String {
        if case .accepted = store.runtimeResult.outcome { return "checkmark.circle.fill" }
        return "xmark.circle.fill"
    }

    private var sampleOutcomeColor: Color {
        if case .accepted = store.runtimeResult.outcome { return .green }
        return .red
    }

    private var tests: some View {
        List {
            Section {
                Button("Run \(document.tests.count) saved tests") {
                    testReport = GrammarTestRunner.run(
                        document.tests, source: document.source,
                        algorithm: document.algorithm, notation: document.notation
                    )
                }.disabled(document.tests.isEmpty || store.frontEnd.hasErrors)
            }
            Section("Saved tests") {
                ForEach(document.tests) { test in
                    VStack(alignment: .leading) {
                        Text(test.name)
                        Text(test.input).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
            if let report = testReport {
                Section("Results — \(report.passed) passed, \(report.failed) failed") {
                    ForEach(report.results) { result in
                        Label(result.name, systemImage: result.status == .passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result.status == .passed ? .green : .red)
                    }
                }
            }
        }
    }

    private var visuals: some View {
        let rules = GrammarDiagramAdapter.availableRules(in: store.currentCompilationSnapshot)
        return VStack(spacing: 0) {
            Picker("Rule", selection: selectedRuleBinding(rules)) {
                ForEach(rules, id: \.self) { Text($0).tag($0 as String?) }
            }.padding()
            Divider()
            if let rule = replSession.selectedRule ?? rules.first,
               let diagram = GrammarDiagramAdapter.diagram(for: rule, in: store.currentCompilationSnapshot) {
                ScrollView([.horizontal, .vertical]) {
                    SwiftUIRenderer().render(model: diagram.model).padding(24)
                }
                .frame(maxHeight: .infinity)
            } else {
                ContentUnavailableView("No rule diagram", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if replSession.transcript.isEmpty {
                        Text("Enter source text to parse, or :help for commands.").foregroundStyle(.secondary)
                    }
                    ForEach(replSession.transcript) { entry in
                        Text(entry.text).font(.caption.monospaced())
                            .foregroundStyle(entry.kind == .error ? .red : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding()
            }.frame(minHeight: 100, maxHeight: 190)
            HStack {
                TextField("Grammar REPL input", text: $replCommand).textFieldStyle(.roundedBorder)
                    .onSubmit(submitREPL)
                Button("Run", action: submitREPL).buttonStyle(.borderedProminent)
            }.padding()
        }.onAppear(perform: refreshREPL)
    }

    private var sourceBinding: Binding<String> {
        Binding(get: { document.source }, set: { value in
            document.source = value
            store.updateSource(value)
        })
    }

    private var sampleBinding: Binding<String> {
        Binding(get: { store.sampleInput }, set: { value in
            store.sampleInput = value
            if let index = document.samples.firstIndex(where: { $0.id == document.selectedSampleID }) {
                document.samples[index].input = value
            }
            store.parseSample()
        })
    }

    private func selectedRuleBinding(_ rules: [String]) -> Binding<String?> {
        Binding(get: { replSession.selectedRule ?? rules.first }, set: { value in
            guard let value else { return }
            _ = replSession.submit(":rule \(value)")
        })
    }

    private func setAlgorithm(_ algorithm: LRAlgorithm) {
        store.algorithm = algorithm
        document.algorithm = algorithm.rawValue
        refreshREPL()
    }

    private func setNotation(_ notation: GrammarSourceNotation) {
        store.notation = notation
        document.notation = notation
        refreshREPL()
    }

    private func refreshREPL() {
        replSession = GrammarREPLSession(compilation: GrammarWorkbenchAPI.compile(.init(
            source: document.source,
            algorithm: GrammarAlgorithm(rawValue: document.algorithm) ?? .lalr,
            notation: document.notation
        )), selectedRule: replSession.selectedRule)
    }

    private func submitREPL() {
        _ = replSession.submit(replCommand)
        replCommand = ""
    }
}
#endif
