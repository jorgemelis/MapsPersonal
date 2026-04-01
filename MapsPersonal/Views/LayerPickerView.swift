import SwiftUI

// MARK: - Layer Picker

struct LayerPickerView: View {
    @Bindable var mapState: MapState
    let offlineMaps: OfflineMapsManager
    let onActivate: (String, String) -> Void
    let onDeactivate: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Base layer (dropdown)
                Section("Mapa base") {
                    Picker("Mapa base", selection: $mapState.activeBaseLayer) {
                        ForEach(MapLayer.baseLayers) { layer in
                            Text(layer.displayName).tag(layer)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // Terrain layers
                Section("Terreno") {
                    Toggle("Picos", isOn: $mapState.showPeaks)
                }

                // Overlay layers (online)
                Section("Capas superpuestas") {
                    ForEach(MapLayer.overlayLayers) { layer in
                        VStack {
                            Toggle(layer.displayName, isOn: Binding(
                                get: { mapState.activeOverlays.contains(layer) },
                                set: { _ in mapState.toggleOverlay(layer) }
                            ))

                            if mapState.activeOverlays.contains(layer) {
                                HStack {
                                    Text("Opacidad")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Slider(
                                        value: Binding(
                                            get: { mapState.opacityFor(layer) },
                                            set: { mapState.overlayOpacity[layer] = $0 }
                                        ),
                                        in: 0.1...1.0
                                    )
                                }
                            }
                        }
                    }
                }

                // Offline maps (MBTiles)
                if !offlineMaps.availableMaps.isEmpty {
                    Section("Mapas offline") {
                        ForEach(offlineMaps.availableMaps) { map in
                            VStack {
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
                                                if let url = offlineMaps.activate(map.id) {
                                                    onActivate(map.id, url)
                                                }
                                            } else {
                                                offlineMaps.deactivate(map.id)
                                                onDeactivate(map.id)
                                            }
                                        }
                                    ))
                                    .labelsHidden()
                                }

                                if map.isActive {
                                    HStack {
                                        Text("Opacidad")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Slider(
                                            value: Binding(
                                                get: { mapState.dynamicOverlayOpacity[map.id] ?? 0.7 },
                                                set: { mapState.dynamicOverlayOpacity[map.id] = $0 }
                                            ),
                                            in: 0.1...1.0
                                        )
                                    }
                                }
                            }
                        }

                        Button("Buscar nuevos mapas") {
                            offlineMaps.scan()
                        }
                    }
                }

                // Reset
                Section {
                    Button("Restablecer ajustes", role: .destructive) {
                        mapState.resetToDefaults()
                    }
                }
            }
            .navigationTitle("Capas")
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
