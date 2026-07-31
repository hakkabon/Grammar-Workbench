import SwiftUI
import AppKit

public struct ArtifactExplorerView: View {
    @State private var store: ExplorerStore
    @State private var tab = ExplorerTab.automaton
    @State private var exportMessage: String?
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
            sampleInput: selectedInput,
            documentName: documentName
        ))
    }

    enum ExplorerTab: String, CaseIterable, Identifiable {
        case analysis = "Analysis", automaton = "Automaton", table = "Table", decisions = "Decisions", sample = "Sample"
        var id: Self { self }
    }

    public var body: some View {
        NavigationSplitView {
            sourceSidebar
        } content: {
            VStack(spacing: 0) {
                Picker("View", selection: $tab) { ForEach(ExplorerTab.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).padding()
                Divider()
                selectedTab
            }
            .navigationTitle("Artifact Explorer")
        } detail: {
            inspector
                .navigationTitle("Inspector")
        }
        .toolbar {
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
            }
            ToolbarItem { Button("Export HTML", systemImage: "square.and.arrow.up", action: exportHTML) }
        }
        .alert("Export", isPresented: Binding(get: { exportMessage != nil }, set: { if !$0 { exportMessage = nil } })) {
            Button("OK") { exportMessage = nil }
        } message: { Text(exportMessage ?? "") }
        .onChange(of: document?.wrappedValue.source) { _, source in
            if let source { store.updateSource(source) }
        }
    }

    private var sourceSidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(store.documentName, systemImage: "doc.text").font(.headline).padding(.horizontal)
            GrammarSourceEditor(
                text: sourceBinding,
                diagnostics: store.frontEnd.diagnostics,
                selectedRange: store.sourceSelection,
                completions: GrammarEditorIntelligence.completions(for: store.frontEnd),
                isEditable: document != nil
            )
                .frame(minHeight: 280)
                .accessibilityLabel(document == nil ? "Read-only grammar source" : "Editable grammar source")
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
                            let fixes = GrammarEditorIntelligence.quickFixes(for: diagnostic, source: sourceBinding.wrappedValue)
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

    @ViewBuilder private var selectedTab: some View {
        switch tab {
        case .analysis: analysisView
        case .automaton:
            AutomatonView(artifact: store.artifact, selection: store.selection) { store.select(.state($0)) }
        case .table: tableView
        case .decisions: decisionsView
        case .sample: sampleView
        }
    }

    private var analysisView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let grammar = store.frontEnd.grammar, let analysis = store.frontEnd.analysis {
                    validationSummary(grammar)
                    Divider()
                    LabeledContent("Start symbol", value: grammar.startSymbol)
                    LabeledContent(
                        "Terminal mode",
                        value: grammar.usesExplicitTokens ? "Explicit (%token)" : "Inferred (legacy)"
                    )
                    Text("Productions").font(.headline)
                    ForEach(grammar.productions) { production in
                        Button(production.text) {
                            store.select(.production(.init(rawValue: production.id + 1)))
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

    private var tableView: some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(horizontalSpacing: 1, verticalSpacing: 1) {
                GridRow {
                    tableText("State", header: true)
                    ForEach(store.artifact.terminals + store.artifact.nonterminals, id: \.self) { tableText($0, header: true) }
                }
                ForEach(store.artifact.states) { state in
                    GridRow {
                        Button(state.id.description) { store.select(.state(state.id)) }.frame(width: 60, height: 32)
                        ForEach(store.artifact.terminals + store.artifact.nonterminals, id: \.self) { symbol in
                            let id = CellID(state: state.id, symbol: symbol)
                            let cell = store.artifact.cell(id)
                            Button(cell?.actions.map(\.label).joined(separator: "/") ?? "") { store.select(.cell(id)) }
                                .buttonStyle(.plain).frame(width: 74, height: 32)
                                .background(cell?.isConflict == true ? Color.red.opacity(0.22) : Color(nsColor: .controlBackgroundColor))
                                .accessibilityLabel("State \(state.id.rawValue), symbol \(symbol), \(cell?.actions.map(\.label).joined(separator: " or ") ?? "empty")")
                        }
                    }
                }
            }.padding()
        }
    }

    private func tableText(_ text: String, header: Bool) -> some View {
        Text(text).font(header ? .headline : .body).frame(width: 74, height: 32).background(Color(nsColor: .controlBackgroundColor))
    }

    private var decisionsView: some View {
        List(store.artifact.decisions) { decision in
            Button { store.select(.decision(decision.id)) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Label(decision.title, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("Witness: \(decision.witness.joined(separator: " "))").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                }.padding(.vertical, 5)
            }.buttonStyle(.plain)
        }.overlay { if store.artifact.decisions.isEmpty { ContentUnavailableView("No conflicts", systemImage: "checkmark.seal") } }
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
                    TextField("Whitespace-separated terminal tokens", text: sampleInputBinding)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit { store.parseSample() }
                    Button("Parse", systemImage: "play.fill") { store.parseSample() }
                }
                Label(store.runtimeResult.outcome.label, systemImage: outcomeIcon)
                    .foregroundStyle(outcomeColor)
                if case .rejected(_, let expected) = store.runtimeResult.outcome, !expected.isEmpty {
                    Text("Expected: \(expected.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                Text("Parse tree").font(.headline)
                ScrollView {
                    Text(store.runtimeResult.tree?.rendered() ?? "No accepted parse tree.")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer()
            }.padding()
            replayView(frames: store.runtimeResult.frames)
        }
    }

    private var outcomeIcon: String {
        switch store.runtimeResult.outcome {
        case .accepted: "checkmark.circle.fill"
        case .rejected: "xmark.octagon.fill"
        case .conflict: "arrow.triangle.branch"
        case .looping: "repeat.circle.fill"
        }
    }

    private var outcomeColor: Color {
        switch store.runtimeResult.outcome {
        case .accepted: .green
        case .rejected: .red
        case .conflict: .orange
        case .looping: .purple
        }
    }

    @ViewBuilder private var inspector: some View {
        if let selection = store.selection {
            ScrollView { VStack(alignment: .leading, spacing: 14) { inspectorContent(selection) }.padding().frame(maxWidth: .infinity, alignment: .leading) }
        } else { ContentUnavailableView("Select an artifact", systemImage: "cursorarrow.click") }
    }

    @ViewBuilder private func inspectorContent(_ selection: ArtifactIdentity) -> some View {
        switch selection {
        case .state(let id):
            Text(id.description).font(.title2.bold())
            ForEach(store.artifact.state(id)?.items ?? []) { item in
                Button(item.text) { store.select(.production(item.production)) }.buttonStyle(.plain).font(.system(.body, design: .monospaced))
            }
            Text("Outgoing transitions").font(.headline)
            ForEach(store.artifact.transitions.filter { $0.from == id }) { transition in
                Button("\(transition.symbol) → \(transition.to)") { store.select(.state(transition.to)) }.buttonStyle(.link)
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
                Text(decision.explanation)
                conflictGraphic(decision)
                Text("Witness: \(decision.witness.joined(separator: " "))").font(.system(.body, design: .monospaced))
                Picker("Branch", selection: $store.selectedBranch) { ForEach(decision.branches.indices, id: \.self) { Text("Branch \($0 + 1)").tag($0) } }.pickerStyle(.segmented)
                replayView(frames: decision.branches[min(store.selectedBranch, decision.branches.count - 1)])
            }
        case .traceStep(let index): Text("Trace step \(index)")
        }
    }

    private func conflictGraphic(_ decision: ConflictDecision) -> some View {
        VStack(spacing: 8) {
            Text(decision.cell.state.description).padding(8).background(.blue.opacity(0.2)).clipShape(Capsule())
            HStack {
                ForEach(decision.branches.indices, id: \.self) { index in
                    Text((store.artifact.cell(decision.cell)?.actions[safe: index])?.label ?? "Branch \(index + 1)")
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
                    if let state = frame.state { Button("State \(state)") { store.select(.state(state)) }.buttonStyle(.link) }
                    if let cell = frame.cell { Button("Cell \(cell.symbol)") { store.select(.cell(cell)) }.buttonStyle(.link) }
                    if let production = frame.production { Button("Production \(production.rawValue)") { store.select(.production(production)) }.buttonStyle(.link) }
                }
            }
        }.padding()
    }

    private func exportHTML() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.html]; panel.nameFieldStringValue = "grammar-artifact.html"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try HTMLExporter.render(store.artifact, runtime: store.runtimeResult).write(to: url, atomically: true, encoding: .utf8); exportMessage = "Exported to \(url.lastPathComponent)." }
        catch { exportMessage = "Could not export: \(error.localizedDescription)" }
    }

    private func openGrammar() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let source = try String(contentsOf: url, encoding: .utf8)
            store.load(source: source, documentName: url.lastPathComponent)
            tab = .analysis
        } catch {
            exportMessage = "Could not open \(url.lastPathComponent): \(error.localizedDescription)"
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

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
