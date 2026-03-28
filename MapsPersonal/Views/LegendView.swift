import SwiftUI

// MARK: - Legend View

struct LegendView: View {
    @State private var legends: [LegendFile] = []
    @State private var selectedLegend: LegendFile?
    @Environment(\.dismiss) private var dismiss

    struct LegendFile: Identifiable {
        let id = UUID()
        let name: String
        let url: URL
    }

    var body: some View {
        NavigationStack {
            Group {
                if legends.isEmpty {
                    ContentUnavailableView {
                        Label("Sin leyendas", systemImage: "map")
                    } description: {
                        Text("Descarga leyendas desde el Control Center del Mac y se sincronizarán vía iCloud.")
                    }
                } else if let selected = selectedLegend {
                    ScrollView([.horizontal, .vertical]) {
                        if let data = try? Data(contentsOf: selected.url),
                           let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .navigationTitle(selected.name)
                } else {
                    List(legends) { legend in
                        Button {
                            selectedLegend = legend
                        } label: {
                            Label(legend.name, systemImage: "doc.richtext")
                        }
                    }
                }
            }
            .navigationTitle(selectedLegend == nil ? "Leyendas" : selectedLegend!.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if selectedLegend != nil {
                        Button("Atrás") { selectedLegend = nil }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
        .onAppear { scanLegends() }
    }

    private func scanLegends() {
        guard let container = FileManager.default.url(
            forUbiquityContainerIdentifier: "iCloud.com.jorge.mapspersonal2026"
        ) else { return }

        let legendsDir = container.appendingPathComponent("Documents/Legends")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: legendsDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return }

        legends = files
            .filter { ["jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in
                let name = url.deletingPathExtension().lastPathComponent
                    .replacingOccurrences(of: "_", with: " ")
                return LegendFile(name: name, url: url)
            }

        // Auto-select if only one
        if legends.count == 1 {
            selectedLegend = legends.first
        }
    }
}
