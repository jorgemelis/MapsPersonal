import SwiftUI
import CoreLocation

// MARK: - Content View

struct ContentView: View {
    @State private var mapState = MapState()
    @State private var locationService = LocationService()
    @State private var trackRecorder: TrackRecorder?
    @State private var offlineMaps = OfflineMapsManager()
    @State private var weather = WeatherService()
    @State private var showLayerPicker = false
    @State private var showOfflineMaps = false
    @State private var showStats = false
    @State private var showWeather = false
    @State private var coordinateText = ""

    var body: some View {
        ZStack {
            // Map
            MapViewRepresentable(
                mapState: mapState,
                trackRecorder: trackRecorder ?? TrackRecorder(locationService: locationService),
                onCameraChange: { coord, zoom in
                    coordinateText = String(format: "%.5f, %.5f  z%.1f", coord.latitude, coord.longitude, zoom)
                }
            )
            .ignoresSafeArea()

            // UI overlays
            VStack(spacing: 8) {
                // Weather panel (toggled from bottom bar)
                if showWeather, weather.temperature != nil {
                    WeatherBarView(weather: weather)
                        .padding(.horizontal)
                        .padding(.top, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()

                // Stats panel (visible when recording or track exists)
                if let recorder = trackRecorder,
                   showStats,
                   (recorder.isRecording || recorder.currentTrack != nil) {
                    TrackStatsView(recorder: recorder)
                        .padding(.horizontal)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Track controls
                if let recorder = trackRecorder {
                    TrackControlView(
                        recorder: recorder,
                        onStart: {
                            recorder.startRecording()
                            showStats = true
                        },
                        onStop: { recorder.stopRecording() },
                        onSave: {
                            if let track = recorder.saveTrack() {
                                mapState.savedTracks.append(track)
                            }
                            showStats = false
                        },
                        onDiscard: {
                            recorder.discardTrack()
                            showStats = false
                        }
                    )
                    .padding(.horizontal)
                }

                // Bottom bar: coordinates + buttons
                HStack {
                    Text(coordinateText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Spacer()

                    // Toggle stats panel
                    if let recorder = trackRecorder,
                       (recorder.isRecording || recorder.currentTrack != nil) {
                        Button {
                            withAnimation { showStats.toggle() }
                        } label: {
                            Image(systemName: showStats ? "chart.bar.fill" : "chart.bar")
                                .font(.title3)
                                .padding(8)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }

                    // Weather toggle
                    if weather.temperature != nil {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showWeather.toggle()
                            }
                        } label: {
                            Image(systemName: showWeather ? "cloud.sun.fill" : "cloud.sun")
                                .font(.title3)
                                .padding(8)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }

                    // Offline maps
                    Button {
                        showOfflineMaps = true
                    } label: {
                        Image(systemName: "arrow.down.circle")
                            .font(.title3)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }

                    // Center on user
                    Button {
                        mapState.isFollowingUser.toggle()
                    } label: {
                        Image(systemName: mapState.isFollowingUser ? "location.fill" : "location")
                            .font(.title3)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }

                    // Layer picker
                    Button {
                        showLayerPicker = true
                    } label: {
                        Image(systemName: "square.3.layers.3d")
                            .font(.title3)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .onAppear {
            trackRecorder = TrackRecorder(locationService: locationService)
            locationService.requestAuthorization()
            offlineMaps.scan()
            autoActivateMaps()

            // Weather: fetch on first location, then every 10 min
            weather.startAutoRefresh {
                locationService.currentLocation?.coordinate
                    ?? (mapState.centerCoordinate.latitude != 40.4168 ? mapState.centerCoordinate : nil)
            }
        }
        .sheet(isPresented: $showLayerPicker) {
            LayerPickerView(mapState: mapState)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showOfflineMaps) {
            OfflineMapsView(
                manager: offlineMaps,
                onActivate: { mapId, url in
                    mapState.dynamicOfflineLayers[mapId] = url
                    mapState.activeDynamicOverlays.insert(mapId)
                },
                onDeactivate: { mapId in
                    mapState.activeDynamicOverlays.remove(mapId)
                    mapState.dynamicOfflineLayers.removeValue(forKey: mapId)
                }
            )
            .presentationDetents([.medium, .large])
        }
    }

    /// Start tile servers for maps that were active in previous session
    private func autoActivateMaps() {
        let savedActive = mapState.activeDynamicOverlays

        for map in offlineMaps.availableMaps {
            // Only activate maps that were active last session (or all if first launch)
            let shouldActivate = savedActive.isEmpty || savedActive.contains(map.id)
            guard shouldActivate else { continue }

            if let url = offlineMaps.activate(map.id) {
                mapState.dynamicOfflineLayers[map.id] = url
                mapState.activeDynamicOverlays.insert(map.id)

                // Bridge: also populate offlineTileURLs for static layers
                let name = map.name.lowercased()
                if name.contains("geologico") || name.contains("magna") {
                    mapState.offlineTileURLs[.igmeGeologicalOffline] = url
                } else if name.contains("ign") || name.contains("mtn") {
                    mapState.offlineTileURLs[.ignMTNOffline] = url
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
