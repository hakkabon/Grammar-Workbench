#if os(macOS)
import SwiftUI
import GrammarDiagramKit

@MainActor
struct GrammarDiagramREPLView: View {
    let compilation: GrammarCompilation
    let onSelectSource: (SourceRange) -> Void

    @State private var session: GrammarREPLSession
    @State private var command = ""
    @State private var selectedElementIDs: Set<DiagramElementID> = []

    init(compilation: GrammarCompilation, onSelectSource: @escaping (SourceRange) -> Void) {
        self.compilation = compilation
        self.onSelectSource = onSelectSource
        _session = State(initialValue: GrammarREPLSession(compilation: compilation))
    }

    private var rules: [String] { GrammarDiagramAdapter.availableRules(in: compilation) }
    private var diagram: GrammarRuleDiagram? {
        session.selectedRule.flatMap { GrammarDiagramAdapter.diagram(for: $0, in: compilation) }
    }

    var body: some View {
        VSplitView {
            diagramPane.frame(minHeight: 260, idealHeight: 430)
            replPane.frame(minHeight: 220)
        }
        .onChange(of: compilation.request.source) { _, _ in
            session = GrammarREPLSession(compilation: compilation, selectedRule: session.selectedRule)
            selectedElementIDs = []
        }
    }

    private var diagramPane: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Railroad diagram", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.headline)
                Picker("Rule", selection: ruleBinding) {
                    ForEach(rules, id: \.self) { Text($0).tag($0) }
                }
                .frame(maxWidth: 280)
                Spacer()
                if let selected = selectedElementIDs.first,
                   let source = diagram?.selection(for: selected) {
                    Text(source.symbol ?? "Production \(source.productionID)")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
            .padding(10)
            Divider()
            if let diagram {
                ScrollView([.horizontal, .vertical]) {
                    SwiftUIRenderer(
                        selectedElementIDs: selectedElementIDs,
                        onActivate: { id in
                            Task { @MainActor in activate(id, in: diagram) }
                        }
                    )
                    .render(model: diagram.model)
                    .padding(24)
                }
                .accessibilityIdentifier("grammar-rule-diagram")
            } else {
                ContentUnavailableView(
                    "No rule diagram", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    description: Text("Compile a valid grammar with at least one production.")
                )
            }
        }
    }

    private var replPane: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Grammar REPL", systemImage: "terminal").font(.headline)
                Spacer()
                Button("Clear") { _ = session.submit(":clear") }
                    .disabled(session.transcript.isEmpty)
            }
            .padding(10)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if session.transcript.isEmpty {
                            Text("Enter source text to parse, or :help for commands.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(session.transcript) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(prompt(for: entry.kind)).foregroundStyle(color(for: entry.kind))
                                Text(entry.text).textSelection(.enabled)
                            }
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(entry.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: session.transcript.count) { _, _ in
                    if let id = session.transcript.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            Divider()
            HStack {
                Text("›").font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                TextField("Input or :command", text: $command)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.plain)
                    .onSubmit(submit)
                Button("Run", systemImage: "return", action: submit).labelStyle(.iconOnly)
                    .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(10)
        }
        .accessibilityIdentifier("grammar-repl")
    }

    private var ruleBinding: Binding<String> {
        Binding(
            get: { session.selectedRule ?? rules.first ?? "" },
            set: { value in
                _ = session.submit(":rule \(value)")
                selectedElementIDs = []
            }
        )
    }

    @MainActor
    private func activate(_ id: DiagramElementID, in diagram: GrammarRuleDiagram) {
        selectedElementIDs = [id]
        if let selection = diagram.selection(for: id) {
            onSelectSource(selection.sourceRange)
        }
    }

    private func submit() {
        let value = command
        command = ""
        _ = session.submit(value)
        selectedElementIDs = []
    }

    private func prompt(for kind: GrammarREPLTranscriptKind) -> String {
        switch kind { case .input: "›"; case .result: "✓"; case .information: "·"; case .error: "!" }
    }

    private func color(for kind: GrammarREPLTranscriptKind) -> Color {
        switch kind { case .input: .secondary; case .result: .green; case .information: .blue; case .error: .red }
    }
}
#endif
