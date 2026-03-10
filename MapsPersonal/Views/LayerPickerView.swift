import SwiftUI

// MARK: - Layer Picker

struct LayerPickerView: View {
    @Bindable var mapState: MapState
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

                // Reset
                Section {
                    Button("Restablecer ajustes", role: .destructive) {
                        mapState.resetToDefaults()
                    }
                }

                // Terrain layers
                Section("Terreno") {
                    VStack {
                        Toggle("Hillshade (relieve)", isOn: $mapState.showHillshade)
                        if mapState.showHillshade {
                            HStack {
                                Text("Intensidad")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Slider(value: $mapState.hillshadeOpacity, in: 0.1...1.0)
                            }
                        }
                    }

                    VStack {
                        Toggle("Curvas de nivel", isOn: $mapState.showContours)
                        if mapState.showContours {
                            HStack {
                                Text("Opacidad")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Slider(value: $mapState.contourOpacity, in: 0.1...1.0)
                            }
                        }
                    }
                }

                // Overlay layers (toggleable)
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
}
