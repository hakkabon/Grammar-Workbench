#if canImport(SwiftUI)
import SwiftUI
import GrammarWorkbenchCore

public struct GrammarWorkbenchSettingsView: View {
    @AppStorage("openLastDocument") private var openLastDocument = true
    @AppStorage("confirmArtifactExport") private var confirmArtifactExport = false
    @AppStorage("visualAppearance") private var visualAppearance = GrammarVisualAppearance.system.rawValue
    @AppStorage("reduceGraphMotion") private var reduceGraphMotion = false
    @AppStorage("showGraphMinimap") private var showGraphMinimap = true
    @AppStorage("showGraphEdgeLabels") private var showGraphEdgeLabels = true

    public init() {}

    public var body: some View {
        Form {
            Toggle("Reopen the last document at launch", isOn: $openLastDocument)
            Toggle("Confirm generated artifact exports", isOn: $confirmArtifactExport)
            Picker("Graph appearance", selection: $visualAppearance) {
                ForEach(GrammarVisualAppearance.allCases, id: \.rawValue) {
                    Text($0.rawValue.capitalized).tag($0.rawValue)
                }
            }
            Toggle("Reduce graph animation", isOn: $reduceGraphMotion)
            Toggle("Show graph minimaps", isOn: $showGraphMinimap)
            Toggle("Show graph edge labels", isOn: $showGraphEdgeLabels)
            LabeledContent("Version", value: GrammarWorkbenchRelease.displayVersion)
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 460)
    }
}
#endif
