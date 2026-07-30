import SwiftUI
import AppKit

public struct ArtifactExplorerView: View {
    @State private var store = ExplorerStore()
    @State private var tab = ExplorerTab.automaton
    @State private var exportMessage: String?

    enum ExplorerTab: String, CaseIterable, Identifiable {
        case automaton = "Automaton", table = "Table", decisions = "Decisions", sample = "Sample"
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
            ToolbarItem {
                Picker("LR algorithm", selection: $store.algorithm) { ForEach(LRAlgorithm.allCases) { Text($0.rawValue).tag($0) } }
                    .frame(width: 180)
            }
            ToolbarItem { Button("Export HTML", systemImage: "square.and.arrow.up", action: exportHTML) }
        }
        .alert("Export", isPresented: Binding(get: { exportMessage != nil }, set: { if !$0 { exportMessage = nil } })) {
            Button("OK") { exportMessage = nil }
        } message: { Text(exportMessage ?? "") }
    }

    private var sourceSidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Grammar source", systemImage: "doc.text").font(.headline).padding(.horizontal)
            TextEditor(text: .constant(store.artifact.grammarSource))
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8).background(Color(nsColor: .textBackgroundColor))
                .disabled(true).accessibilityLabel("Read-only grammar source")
            Text("\(store.artifact.productions.count) productions · \(store.artifact.states.count) states")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
        }.padding(.vertical)
    }

    @ViewBuilder private var selectedTab: some View {
        switch tab {
        case .automaton:
            AutomatonView(artifact: store.artifact, selection: store.selection) { store.select(.state($0)) }
        case .table: tableView
        case .decisions: decisionsView
        case .sample: sampleView
        }
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
            VStack(alignment: .leading) { Text("Input").font(.headline); Text(store.artifact.sample.input).font(.system(.body, design: .monospaced)); Divider(); Text("Parse tree").font(.headline); Text(store.artifact.sample.tree).font(.system(.body, design: .monospaced)); Spacer() }.padding()
            replayView(frames: store.artifact.sample.trace)
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
            HStack { ForEach(decision.branches.indices, id: \.self) { index in Text(index == 0 ? "Shift" : "Reduce").frame(maxWidth: .infinity).padding(8).background(index == 0 ? .green.opacity(0.2) : .orange.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 8)) } }
        }.padding().overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.3)))
    }

    private func replayView(frames: [ReplayFrame]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Replay").font(.headline)
            Slider(value: Binding(get: { Double(min(store.replayIndex, max(0, frames.count - 1))) }, set: { store.replayIndex = Int($0) }), in: 0...Double(max(1, frames.count - 1)), step: 1)
            if !frames.isEmpty {
                let frame = frames[min(store.replayIndex, frames.count - 1)]
                LabeledContent("Stack", value: frame.stack.joined(separator: " "))
                LabeledContent("Input", value: frame.remainingInput.joined(separator: " "))
                LabeledContent("Action", value: frame.action)
                if let state = frame.state { Button("Inspect \(state)") { store.select(.state(state)) }.buttonStyle(.link) }
            }
        }.padding()
    }

    private func exportHTML() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.html]; panel.nameFieldStringValue = "grammar-artifact.html"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try HTMLExporter.render(store.artifact).write(to: url, atomically: true, encoding: .utf8); exportMessage = "Exported to \(url.lastPathComponent)." }
        catch { exportMessage = "Could not export: \(error.localizedDescription)" }
    }
}
