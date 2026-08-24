#if os(macOS)
import SwiftUI
import GrammarDiagramKit

struct InteractiveGrammarExplorerView: View {
    let compilation: GrammarCompilation
    let onSelectSource: (SourceRange) -> Void

    @State private var selectedRule: String
    @State private var query = ""
    @State private var selectedElements: Set<DiagramElementID> = []

    init(compilation: GrammarCompilation, onSelectSource: @escaping (SourceRange) -> Void) {
        self.compilation = compilation
        self.onSelectSource = onSelectSource
        _selectedRule = State(initialValue: compilation.grammar?.startSymbol ?? "")
    }

    private var snapshot: GrammarExplorationSnapshot? {
        try? GrammarInteractiveExplorer.snapshot(compilation, selectedRule: selectedRule)
    }

    var body: some View {
        HSplitView {
            ruleList.frame(minWidth: 230, idealWidth: 280, maxWidth: 360)
            detail.frame(minWidth: 520, maxWidth: .infinity)
        }
        .onChange(of: compilation.request.source) { _, _ in
            selectedRule = compilation.grammar?.startSymbol ?? ""
            selectedElements = []
        }
        .accessibilityIdentifier("interactive-grammar-explorer")
    }

    private var ruleList: some View {
        VStack(spacing: 0) {
            TextField("Find rules, productions, FIRST or FOLLOW", text: $query)
                .textFieldStyle(.roundedBorder).padding(10)
            Divider()
            if let snapshot {
                List(selection: $selectedRule) {
                    ForEach(GrammarInteractiveExplorer.matchingRules(in: snapshot, query: query)) { rule in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.id).font(.body.monospaced())
                                Text("\(rule.productions.count) production\(rule.productions.count == 1 ? "" : "s")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if rule.isStart { Image(systemName: "flag.fill").foregroundStyle(.blue) }
                            if rule.isRecursive { Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90") }
                            if !rule.isReachable || !rule.isProductive {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            }
                        }
                        .tag(rule.id)
                    }
                }
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let snapshot, let rule = snapshot.selected {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header(rule, path: snapshot.pathFromStart)
                    diagramSection(rule)
                    productionsSection(rule)
                    relationshipSection(rule)
                    analysisSection(rule)
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView(
                "Grammar exploration unavailable", systemImage: "scope",
                description: Text("Resolve grammar errors to explore its rules and relationships.")
            )
        }
    }

    private func header(_ rule: GrammarRuleExploration, path: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(rule.id).font(.largeTitle.bold().monospaced())
                if rule.isStart { badge("Start", color: .blue) }
                if rule.isNullable { badge("Nullable", color: .purple) }
                if rule.isRecursive { badge("Recursive", color: .orange) }
                if !rule.isReachable { badge("Unreachable", color: .red) }
                if !rule.isProductive { badge("Unproductive", color: .red) }
            }
            if !path.isEmpty {
                HStack(spacing: 4) {
                    Text("Path from start:").foregroundStyle(.secondary)
                    ForEach(Array(path.enumerated()), id: \.offset) { index, value in
                        if index > 0 { Image(systemName: "chevron.right").font(.caption) }
                        Button(value) { selectRule(value) }.buttonStyle(.link)
                    }
                }.font(.caption)
            }
        }
    }

    private func diagramSection(_ rule: GrammarRuleExploration) -> some View {
        GroupBox("Railroad diagram") {
            if let diagram = GrammarDiagramAdapter.diagram(for: rule.id, in: compilation) {
                ScrollView([.horizontal, .vertical]) {
                    SwiftUIRenderer(
                        selectedElementIDs: selectedElements,
                        onActivate: { id in Task { @MainActor in activate(id, diagram: diagram) } }
                    )
                    .render(model: diagram.model)
                    .padding()
                }.frame(minHeight: 180, maxHeight: 380)
            } else {
                Text("No diagram is available.").foregroundStyle(.secondary)
            }
        }
    }

    private func productionsSection(_ rule: GrammarRuleExploration) -> some View {
        GroupBox("Productions") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rule.productions) { production in
                    Button {
                        onSelectSource(production.range)
                    } label: {
                        Text(production.text).font(.body.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func relationshipSection(_ rule: GrammarRuleExploration) -> some View {
        HStack(alignment: .top, spacing: 14) {
            linkGroup("References", values: rule.outgoingRules)
            linkGroup("Referenced by", values: rule.incomingRules)
            linkGroup("Recursive component", values: rule.recursiveComponent.filter { $0 != rule.id })
        }
    }

    private func analysisSection(_ rule: GrammarRuleExploration) -> some View {
        HStack(alignment: .top, spacing: 14) {
            valueGroup("FIRST", values: rule.first)
            valueGroup("FOLLOW", values: rule.follow)
        }
    }

    private func linkGroup(_ title: String, values: [String]) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 6) {
                if values.isEmpty { Text("None").foregroundStyle(.secondary) }
                ForEach(values, id: \.self) { value in
                    Button(value) { selectRule(value) }.buttonStyle(.link)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity)
    }

    private func valueGroup(_ title: String, values: [String]) -> some View {
        GroupBox(title) {
            Text(values.isEmpty ? "∅" : values.joined(separator: "  "))
                .font(.body.monospaced()).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text).font(.caption.bold()).padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule()).foregroundStyle(color)
    }

    private func selectRule(_ rule: String) {
        selectedRule = rule
        selectedElements = []
    }

    @MainActor private func activate(_ id: DiagramElementID, diagram: GrammarRuleDiagram) {
        selectedElements = [id]
        if let selection = diagram.selection(for: id) { onSelectSource(selection.sourceRange) }
    }
}
#endif
