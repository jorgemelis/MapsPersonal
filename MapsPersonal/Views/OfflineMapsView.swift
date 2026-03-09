import SwiftUI

// MARK: - Offline Maps Manager View

struct OfflineMapsView: View {
    let manager: OfflineMapsManager
    let onActivate: (String, String) -> Void // (mapId, urlTemplate)
    let onDeactivate: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if manager.availableMaps.isEmpty {
                    ContentUnavailableView {
                        Label("Sin mapas offline", systemImage: "map")
                    } description: {
                        Text("Conecta el iPhone al Mac y copia ficheros .mbtiles a MapsPersonal en Finder.")
                    }
                } else {
                    Section("Mapas disponibles") {
                        ForEach(manager.availableMaps) { map in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(map.name)
                                        .font(.body)
                                    Text(formatSize(map.fileSize))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Toggle("", isOn: Binding(
                                    get: { map.isActive },
                                    set: { active in
                                        if active {
                                            if let url = manager.activate(map.id) {
                                                onActivate(map.id, url)
                                            }
                                        } else {
                                            manager.deactivate(map.id)
                                            onDeactivate(map.id)
                                        }
                                    }
                                ))
                                .labelsHidden()
                            }
                        }
                    }

                    Section {
                        Button("Buscar nuevos mapas") {
                            manager.scan()
                        }
                    }
                }
            }
            .navigationTitle("Mapas offline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        if bytes >= 1_048_576 {
            return String(format: "%.1f MB", Double(bytes) / 1_048_576)
        }
        return String(format: "%.0f KB", Double(bytes) / 1024)
    }
}
