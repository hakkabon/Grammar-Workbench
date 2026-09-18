#if os(macOS)
import SwiftUI
import GrammarWorkbenchCore

@MainActor
struct GrammarREPLExperimentExplorerView: View {
    @Bindable var store: ExplorerStore
    let openExperiment: () -> Void

    var body: some View {
        if let artifact = store.experimentArtifact {
            experiment(artifact)
        } else {
            ContentUnavailableView {
                Label("No experiment open", systemImage: "doc.text.magnifyingglass")
            } description: {
                Text("Open a Grammar-REPL experiment to compare engines, inspect semantic results and packed forests, and replay portable parser events.")
            } actions: {
                Button("Open Experiment…") { openExperiment() }.buttonStyle(.borderedProminent)
            }
        }
    }

    private func experiment(_ artifact: GrammarREPLExperimentArtifact) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(artifact)
                summary(artifact.summary)
                engineMatrix(artifact)
                engineInspector(artifact)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("grammar-repl-experiment-explorer")
    }

    private func header(_ artifact: GrammarREPLExperimentArtifact) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: artifact.agreement == .complete ? "checkmark.circle.fill" : "arrow.triangle.branch")
                .font(.largeTitle)
                .foregroundStyle(artifact.agreement == .complete ? .green : .orange)
            VStack(alignment: .leading, spacing: 5) {
                Text(store.experimentName ?? "Grammar-REPL experiment").font(.title2.bold())
                Text(artifact.input.debugDescription).font(.body.monospaced()).textSelection(.enabled)
                Text("Recorded by \(artifact.producer.name) \(artifact.producer.version) · \(artifact.agreement.rawValue)")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Another…") { openExperiment() }
        }
    }

    private func summary(_ summary: GrammarREPLExperimentSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                metric("Engines", summary.engineCount)
                metric("Supported", summary.supportedEngineCount)
                metric("Accepted", summary.acceptedEngineCount)
                metric("Ambiguous", summary.ambiguousEngineCount)
                metric("Max derivations", summary.maximumDerivationCount)
                metric("Max forest nodes", summary.maximumForestNodeCount)
                if let agreement = summary.semanticAgreement {
                    metric("Semantic engines", summary.semanticEvaluatedEngineCount)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(agreement.rawValue).font(.title3.bold())
                        Text("Semantic agreement").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(10).frame(minWidth: 130, alignment: .leading)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 9))
                }
                if let ambiguity = summary.semanticAmbiguity {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ambiguity.rawValue).font(.title3.bold())
                        Text("Semantic ambiguity").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(10).frame(minWidth: 160, alignment: .leading)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 9))
                }
            }
            Label(
                "Recorded fingerprint only. Run `grammar-repl-experiment verify` for semantic verification.",
                systemImage: "checkmark.shield"
            )
            .font(.caption).foregroundStyle(.secondary)
            Text("\(GrammarREPLExperimentArtifact.supportedFingerprintAlgorithm):\(store.experimentArtifact?.fingerprint ?? "")")
                .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }

    private func metric(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(.title3.bold()).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .padding(10).frame(minWidth: 92, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 9))
    }

    private func engineMatrix(_ artifact: GrammarREPLExperimentArtifact) -> some View {
        GroupBox("Engine evidence") {
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 9) {
                    GridRow {
                        Text("Engine"); Text("Capability"); Text("Status")
                        Text("Trees"); Text("Semantics"); Text("Forest"); Text("Ambiguity"); Text("Replay")
                    }.font(.caption.bold()).foregroundStyle(.secondary)
                    Divider().gridCellColumns(8)
                    ForEach(artifact.observations) { observation in
                        GridRow {
                            Button(observation.parser) { store.selectExperimentEngine(observation.parser) }
                                .buttonStyle(.link).font(.body.monospaced())
                            Text(observation.availability.rawValue)
                            statusLabel(observation.contract.status)
                            Text("\(observation.treeFingerprints.count)").monospacedDigit()
                            semanticLabel(artifact.semanticObservation(for: observation.parser))
                            Text(observation.contract.forest.map { "\($0.nodes.count) / \($0.edges.count)" } ?? "—")
                                .monospacedDigit()
                            Text(observation.contract.forest?.isAmbiguous == true ? "yes" : "no")
                            Text("\(observation.contract.replay.count)").monospacedDigit()
                        }
                    }
                }.padding(10)
            }
        }
    }

    private func statusLabel(_ status: GrammarREPLExperimentArtifact.Status) -> some View {
        Label(status.rawValue, systemImage: status == .rejected ? "xmark.circle" : "checkmark.circle")
            .foregroundStyle(status == .rejected ? .red : status == .recovered ? .orange : .green)
    }

    @ViewBuilder private func engineInspector(_ artifact: GrammarREPLExperimentArtifact) -> some View {
        if let selectedID = store.experimentSelectedEngine,
           let observation = artifact.observation(for: selectedID) {
            HStack {
                Picker("Inspect", selection: Binding(
                    get: { selectedID }, set: { store.selectExperimentEngine($0) }
                )) {
                    ForEach(artifact.engines, id: \.self) { Text($0).tag($0) }
                }.frame(maxWidth: 240)
                Picker("Baseline", selection: Binding(
                    get: { store.experimentBaselineEngine ?? artifact.engines[0] },
                    set: { store.selectExperimentBaseline($0) }
                )) {
                    ForEach(artifact.engines, id: \.self) { Text($0).tag($0) }
                }.frame(maxWidth: 240)
                Spacer()
            }
            comparison(artifact, selected: observation)
            semanticInspector(artifact.semanticObservation(for: observation.parser))
            if let reason = observation.unsupportedReason {
                Label(reason, systemImage: "nosign").foregroundStyle(.orange)
            }
            if let forest = observation.contract.forest {
                forestExplorer(forest, parser: observation.parser, replay: observation.contract.replay)
            } else {
                ContentUnavailableView(
                    "No packed forest", systemImage: "point.3.filled.connected.trianglepath.dotted",
                    description: Text("\(observation.parser) recorded a deterministic contract. Use portable replay below to inspect its behavior.")
                ).frame(minHeight: 170)
                replayControls(observation.contract.replay)
            }
        }
    }

    private func semanticLabel(
        _ observation: GrammarREPLExperimentArtifact.SemanticObservation?
    ) -> some View {
        Text(observation.map {
            $0.status == .evaluated || $0.status == .partiallyEvaluated
                ? $0.values.map(\.displayValue).joined(separator: " | ")
                : $0.status.rawValue
        } ?? "—")
        .font(.body.monospaced()).lineLimit(1)
    }

    @ViewBuilder private func semanticInspector(
        _ observation: GrammarREPLExperimentArtifact.SemanticObservation?
    ) -> some View {
        if let observation {
            GroupBox("Compiler semantics") {
                VStack(alignment: .leading, spacing: 7) {
                    Label(
                        observation.status.rawValue,
                        systemImage: observation.status == .evaluated ? "function" : "exclamationmark.triangle"
                    )
                    if let ambiguity = observation.ambiguity {
                        Text("Ambiguity: \(ambiguity.rawValue)")
                            .font(.caption.bold()).foregroundStyle(.secondary)
                    }
                    if !observation.values.isEmpty {
                        Text(observation.values.map(\.displayValue).joined(separator: "\n"))
                            .font(.body.monospaced()).textSelection(.enabled)
                    }
                    ForEach(Array(observation.diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                        Text("\(diagnostic.stage): \(diagnostic.message)")
                            .font(.caption.monospaced()).foregroundStyle(.orange)
                    }
                    if let derivations = observation.derivations {
                        Divider()
                        ForEach(derivations) { derivation in
                            HStack(alignment: .firstTextBaseline) {
                                Text("#\(derivation.index + 1)").monospacedDigit()
                                Text(derivation.syntaxFingerprint).font(.caption.monospaced())
                                if let value = derivation.value {
                                    Text(value.displayValue).font(.body.monospaced())
                                } else if let diagnostic = derivation.diagnostic {
                                    Text("\(diagnostic.stage): \(diagnostic.message)")
                                        .font(.caption.monospaced()).foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                    Text("Recorded Compiler result; Workbench does not re-evaluate semantics.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func comparison(
        _ artifact: GrammarREPLExperimentArtifact,
        selected: GrammarREPLExperimentArtifact.Observation
    ) -> some View {
        let baseline = artifact.observation(for: store.experimentBaselineEngine ?? "") ?? selected
        let delta = GrammarREPLExperimentEngineDelta(baseline: baseline, candidate: selected)
        return GroupBox("Compared with \(baseline.parser)") {
            HStack {
                Image(systemName: delta.agrees ? "equal.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(delta.agrees ? .green : .orange)
                Text(delta.agrees
                     ? "The explorer summaries agree."
                     : "Different: \(delta.differences.map(\.rawValue).joined(separator: ", ")).")
                Spacer()
            }.padding(6)
        }
    }

    private func forestExplorer(
        _ forest: GrammarREPLExperimentArtifact.Forest,
        parser: String,
        replay: [GrammarREPLExperimentArtifact.ReplayEvent]
    ) -> some View {
        let projection = GrammarREPLExperimentForestProjection.project(
            forest, parser: parser,
            collapsedNodeIDs: store.experimentPlayback.collapsedNodeIDs
        )
        let activeNode = replay.indices.contains(store.experimentPlayback.step)
            ? replay[store.experimentPlayback.step].forestNodeID : nil
        return GroupBox("Packed forest") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(projection.graph.nodes.count) visible · \(projection.hiddenNodeCount) hidden")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("Select a node to collapse or expand it.").font(.caption).foregroundStyle(.secondary)
                }
                GrammarREPLExperimentForestGraph(
                    graph: projection.graph, activeNodeID: activeNode,
                    toggleNode: { store.toggleExperimentForestNode($0) }
                ).frame(minHeight: 360)
                replayControls(replay)
            }.padding(6)
        }
    }

    private func replayControls(_ events: [GrammarREPLExperimentArtifact.ReplayEvent]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Button("Previous", systemImage: "chevron.left") { store.stepExperimentReplayBackward() }
                    .labelStyle(.iconOnly).disabled(store.experimentPlayback.step == 0)
                Button("Next", systemImage: "chevron.right") { store.stepExperimentReplayForward() }
                    .labelStyle(.iconOnly).disabled(store.experimentPlayback.step >= max(0, events.count - 1))
                Slider(value: Binding(
                    get: { Double(store.experimentPlayback.step) },
                    set: { store.seekExperimentReplay(to: Int($0.rounded())) }
                ), in: 0...Double(max(1, events.count - 1)), step: 1)
                Text("\(events.isEmpty ? 0 : store.experimentPlayback.step + 1) / \(events.count)")
                    .font(.caption.monospacedDigit()).frame(width: 70)
            }
            if events.indices.contains(store.experimentPlayback.step) {
                let event = events[store.experimentPlayback.step]
                HStack(spacing: 12) {
                    Label(event.kind.rawValue, systemImage: replayIcon(event.kind)).font(.headline)
                    if let token = event.tokenIndex { Text("token \(token)") }
                    if let production = event.productionID { Text("production \(production)") }
                    if let node = event.forestNodeID { Text("node \(node)").lineLimit(1) }
                }.textSelection(.enabled)
            }
        }
    }

    private func replayIcon(_ kind: GrammarREPLExperimentArtifact.ReplayKind) -> String {
        switch kind {
        case .start: "play.fill"
        case .inspect: "magnifyingglass"
        case .consume: "arrow.right.circle"
        case .applyProduction: "arrow.triangle.branch"
        case .discoverAmbiguity: "point.3.filled.connected.trianglepath.dotted"
        case .recover: "cross.case"
        case .accept: "checkmark.circle.fill"
        case .reject: "xmark.circle.fill"
        }
    }
}

private struct GrammarREPLExperimentForestGraph: View {
    let graph: GrammarGraph
    let activeNodeID: String?
    let toggleNode: (String) -> Void

    private var layout: GrammarGraphLayoutSnapshot? {
        try? GrammarGraphLayoutEngine.layout(
            graph,
            options: .init(horizontalGap: 48, verticalGap: 54, direction: .topToBottom)
        )
    }

    var body: some View {
        if let layout {
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        for route in layout.routes {
                            guard let first = route.points.first else { continue }
                            var path = Path()
                            path.move(to: CGPoint(x: first.x, y: first.y))
                            for point in route.points.dropFirst() {
                                path.addLine(to: CGPoint(x: point.x, y: point.y))
                            }
                            context.stroke(path, with: .color(.secondary.opacity(0.65)), lineWidth: 1.4)
                        }
                    }
                    ForEach(layout.nodes) { positioned in
                        Button { toggleNode(positioned.node.id) } label: {
                            VStack(spacing: 2) {
                                Text(positioned.node.label).font(.caption.bold()).lineLimit(1)
                                if let detail = positioned.node.detail {
                                    Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .padding(5)
                            .frame(width: positioned.frame.width, height: positioned.frame.height)
                            .background(
                                positioned.node.id == activeNodeID ? Color.accentColor.opacity(0.22) : Color(nsColor: .controlBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 7)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 7).stroke(
                                    positioned.node.metadata["ambiguous"] == "true" ? .orange : .secondary,
                                    lineWidth: positioned.node.id == activeNodeID ? 3 : 1
                                )
                            }
                        }
                        .buttonStyle(.plain)
                        .position(x: positioned.frame.midX, y: positioned.frame.midY)
                        .help(positioned.node.id)
                    }
                }
                .frame(width: max(320, layout.width), height: max(320, layout.height))
            }
        } else {
            ContentUnavailableView(
                "Forest layout unavailable", systemImage: "exclamationmark.triangle",
                description: Text("The recorded evidence remains available in the engine matrix and replay.")
            )
        }
    }
}
#endif
