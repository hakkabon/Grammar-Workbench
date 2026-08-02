import SwiftUI
import AppKit

public struct ArtifactExplorerView: View {
    @State private var store: ExplorerStore
    @State private var tab = ExplorerTab.automaton
    @State private var exportMessage: String?
    @State private var selectedTestID: UUID?
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
        case analysis = "Analysis", automaton = "Automaton", table = "Table", decisions = "Decisions", sample = "Sample", tests = "Tests"
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
            ToolbarItem {
                Menu("Interchange", systemImage: "arrow.left.arrow.right") {
                    if document != nil {
                        Button("Export Project JSON…", action: exportInterchange)
                        Button("Import Project JSON…", action: importInterchange)
                    }
                    Button("Export Artifact JSON…", action: exportArtifactInterchange)
                    Divider()
                    Button("Generate Swift Parser…", action: exportSwiftParser)
                }
            }
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
        case .tests: testsView
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
        return Button(state.description) { store.select(.state(state)) }
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
        return Button { store.select(.cell(id)) } label: {
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
                Button { store.select(.decision(decision.id)) } label: {
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
                                store.select(.state(diagnostic.state))
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
                Spacer()
            }.padding()
            replayView(frames: store.runtimeResult.frames)
        }
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

    @ViewBuilder private var inspector: some View {
        if let selection = store.selection {
            ScrollView { VStack(alignment: .leading, spacing: 14) { inspectorContent(selection) }.padding().frame(maxWidth: .infinity, alignment: .leading) }
        } else { ContentUnavailableView("Select an artifact", systemImage: "cursorarrow.click") }
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
                        store.select(.decision(decision.id))
                    }.buttonStyle(.link)
                }
            }
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
        do { try HTMLExporter.render(store.artifact, runtime: store.runtimeResult, lexer: store.lexerResult, testReport: store.testReport).write(to: url, atomically: true, encoding: .utf8); exportMessage = "Exported to \(url.lastPathComponent)." }
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
                source: store.frontEnd.source, algorithm: store.algorithm.rawValue
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
                source: store.frontEnd.source, algorithm: algorithm
            ))
            let source = try compilation.generateSwiftParser()
            try source.write(to: url, atomically: true, encoding: .utf8)
            exportMessage = "Generated Swift parser at \(url.lastPathComponent)."
        } catch {
            exportMessage = "Could not generate parser: \(error.localizedDescription)"
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

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
