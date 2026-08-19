#if os(macOS)
import SwiftUI

struct GrammarVisualProductGalleryView: View {
    let timeline: GrammarParserVisualizationTimeline?
    @AppStorage("visualAppearance") private var appearance = GrammarVisualAppearance.system.rawValue
    @AppStorage("reduceGraphMotion") private var reduceMotion = false
    @AppStorage("showGraphMinimap") private var showMinimap = true
    @AppStorage("showGraphEdgeLabels") private var showEdgeLabels = true

    private var selectedAppearance: GrammarVisualAppearance {
        GrammarVisualAppearance(rawValue: appearance) ?? .system
    }
    private var palette: GrammarVisualPalette {
        GrammarVisualDesignSystem.palette(for: selectedAppearance)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Visual product gallery").font(.largeTitle.bold())
                    Text("One review surface for color, controls, graph presentation, motion, accessibility, and export readiness.")
                        .foregroundStyle(.secondary)
                }
                settings
                paletteGallery
                componentGallery
                auditGallery
                if let timeline {
                    GroupBox("Interactive parser graph") {
                        GrammarParserVisualizationView(timeline: timeline)
                            .frame(minHeight: 430)
                            .accessibilityIdentifier("visual-gallery-parser-preview")
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("visual-product-gallery")
    }

    private var settings: some View {
        GroupBox("Presentation preferences") {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow {
                    Text("Appearance").font(.headline)
                    Picker("Appearance", selection: $appearance) {
                        ForEach(GrammarVisualAppearance.allCases, id: \.rawValue) {
                            Text($0.rawValue.capitalized).tag($0.rawValue)
                        }
                    }.labelsHidden().frame(width: 180)
                }
                GridRow { Text("Motion").font(.headline); Toggle("Reduce animation", isOn: $reduceMotion) }
                GridRow { Text("Graph detail").font(.headline); HStack { Toggle("Minimap", isOn: $showMinimap); Toggle("Edge labels", isOn: $showEdgeLabels) } }
            }.padding(8)
        }
    }

    private var paletteGallery: some View {
        GroupBox("Semantic colors") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                swatch("Canvas", palette.canvas)
                swatch("Surface", palette.surface)
                swatch("Text", palette.text)
                swatch("Secondary", palette.secondaryText)
                swatch("Accent", palette.accent)
                swatch("Success", palette.success)
                swatch("Warning", palette.warning)
                swatch("Danger", palette.danger)
                swatch("Active", palette.active)
            }.padding(8)
        }
    }

    private var componentGallery: some View {
        GroupBox("Product states") {
            HStack(alignment: .top, spacing: 14) {
                productCard("Ready", icon: "checkmark.seal.fill", color: .green, detail: "Grammar and examples are ready to explore.")
                productCard("Needs attention", icon: "exclamationmark.triangle.fill", color: .orange, detail: "A source problem needs a clear next action.")
                productCard("Unavailable", icon: "rectangle.slash", color: .secondary, detail: "Explain why the surface has no content.")
                VStack(alignment: .leading, spacing: 10) {
                    Label("Background work", systemImage: "gearshape.2").font(.headline)
                    ProgressView(value: 0.62)
                    Text("Building parser artifacts…").font(.caption).foregroundStyle(.secondary)
                }.productCardStyle()
            }.padding(8)
        }
    }

    private var auditGallery: some View {
        let report = timeline.map { GrammarVisualProductAuditor.audit(graph: $0.graph, timeline: $0) }
        return GroupBox("Accessibility and visual audit") {
            HStack(spacing: 14) {
                Label(
                    report?.passes == false ? "Review required" : "Audit passes",
                    systemImage: report?.passes == false ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                ).foregroundStyle(report?.passes == false ? .orange : .green).font(.headline)
                Text("\(report?.errorCount ?? 0) errors · \(report?.warningCount ?? 0) warnings")
                    .foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Text("Design system v\(GrammarVisualDesignSystem.schemaVersion)")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(8)
        }
    }

    private func swatch(_ name: String, _ hex: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 7).fill(Color(grammarHex: hex)).frame(width: 34, height: 34)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(.primary.opacity(0.25)))
            VStack(alignment: .leading) { Text(name).font(.caption.bold()); Text(hex).font(.caption2.monospaced()).foregroundStyle(.secondary) }
        }
    }
    private func productCard(_ title: String, icon: String, color: Color, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(color)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }.productCardStyle()
    }
}

private extension View {
    func productCardStyle() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.3)))
    }
}

private extension Color {
    init(grammarHex: String) {
        let value = UInt64(grammarHex.dropFirst(), radix: 16) ?? 0
        self.init(
            .sRGB, red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255, opacity: 1
        )
    }
}
#endif
