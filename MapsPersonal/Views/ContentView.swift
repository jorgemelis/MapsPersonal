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
    @State private var showTrackManager = false
    @State private var shareFileURL: URL?
    @State private var coordinateText = ""
    @State private var mapBearing: Double = 0
    @State private var mapPitch: Double = 0
    @State private var tractive = TractiveService()

    var body: some View {
        ZStack {
            // Map
            MapViewRepresentable(
                mapState: mapState,
                trackRecorder: trackRecorder ?? TrackRecorder(locationService: locationService),
                tractiveService: tractive.isConnected ? tractive : nil,
                onCameraChange: { coord, zoom, bearing, pitch in
                    DispatchQueue.main.async {
                        coordinateText = String(format: "%.5f, %.5f  z%.1f", coord.latitude, coord.longitude, zoom)
                        mapBearing = bearing
                        mapPitch = pitch
                    }
                },
                terrainVersion: mapState.terrainVersion,
                petPositionTimestamp: tractive.lastPositionUpdate
            )
            .ignoresSafeArea()

            // Compass button (top-right)
            VStack {
                HStack {
                    Spacer()
                    Button {
                        mapState.resetNorthRequest = true
                    } label: {
                        CompassView(bearing: mapBearing)
                            .frame(width: 40, height: 40)
                    }
                    .opacity(mapBearing != 0 || mapPitch != 0 ? 1.0 : 0.3)
                    .animation(.easeInOut(duration: 0.2), value: mapBearing)
                    .padding(.trailing, 12)
                    .padding(.top, 50)
                }
                Spacer()
            }

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

                // Stats panel (expanded, tap to collapse)
                if let recorder = trackRecorder,
                   (recorder.isRecording || recorder.currentTrack != nil),
                   showStats {
                    TrackStatsView(recorder: recorder)
                        .padding(.horizontal)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onTapGesture {
                            withAnimation { showStats = false }
                        }
                }

                // Recording compact bar (one line: stats + stop/save)
                if let recorder = trackRecorder,
                   (recorder.isRecording || recorder.currentTrack != nil) {
                    TrackStatsCompactView(
                        recorder: recorder,
                        onStop: {
                            recorder.stopRecording()
                            if tractive.isLiveTracking {
                                Task { await tractive.stopHikeMode() }
                            }
                        },
                        onSave: {
                            if let track = recorder.saveTrack() {
                                mapState.savedTracks.append(track)
                                shareFileURL = recorder.lastSavedFileURL
                            }
                            showStats = false
                        },
                        onDiscard: {
                            recorder.discardTrack()
                            showStats = false
                        }
                    )
                    .padding(.horizontal)
                    .onTapGesture {
                        withAnimation { showStats.toggle() }
                    }
                }

                // Bottom bar: buttons + record
                HStack {
                    Spacer()

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

                    // Pet tracker menu
                    if tractive.isConnected {
                        Menu {
                            ForEach(tractive.pets) { pet in
                                Button {
                                    tractive.togglePet(pet.id)
                                } label: {
                                    Label(
                                        "\(pet.emoji) \(pet.name)\(pet.batteryLevel.map { " \($0)%" } ?? "")",
                                        systemImage: pet.isVisible ? "checkmark.circle.fill" : "circle"
                                    )
                                }
                            }
                        } label: {
                            Image(systemName: "pawprint.fill")
                                .font(.title3)
                                .padding(8)
                                .background(
                                    tractive.visiblePets.isEmpty
                                        ? AnyShapeStyle(.ultraThinMaterial)
                                        : AnyShapeStyle(.orange.opacity(0.3)),
                                    in: Circle()
                                )
                        }
                    }

                    // Start recording (only when idle)
                    if let recorder = trackRecorder,
                       !recorder.isRecording && recorder.currentTrack == nil {
                        Button {
                            recorder.startRecording()
                            showStats = false
                            // Activate LIVE tracking on visible pets
                            if tractive.isConnected && !tractive.visiblePets.isEmpty {
                                Task { await tractive.startHikeMode() }
                            }
                        } label: {
                            Image(systemName: "record.circle")
                                .font(.title3)
                                .foregroundStyle(.red)
                                .padding(8)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }

                    // Saved tracks
                    Button {
                        showTrackManager = true
                    } label: {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.title3)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
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

                    // Location: tap = toggle follow mode
                    Button {
                        mapState.isFollowingUser.toggle()
                    } label: {
                        Image(systemName: mapState.isFollowingUser ? "location.fill" : "location")
                            .font(.title3)
                            .padding(8)
                            .background(mapState.isFollowingUser ? AnyShapeStyle(.blue.opacity(0.3)) : AnyShapeStyle(.ultraThinMaterial), in: Circle())
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

                // Coordinates & zoom (subtle line below buttons)
                Text(coordinateText)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
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

            // Tractive: connect and start auto-refresh
            Task {
                await tractive.connect()
                if tractive.isConnected {
                    tractive.startAutoRefresh()
                }
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
        .sheet(isPresented: Binding(
            get: { shareFileURL != nil },
            set: { if !$0 { shareFileURL = nil } }
        )) {
            if let url = shareFileURL {
                ShareSheet(items: [url])
            }
        }
        .sheet(isPresented: $showTrackManager) {
            TrackManagerView()
                .presentationDetents([.medium, .large])
        }
    }

    /// Start tile servers only for maps that were explicitly active in previous session
    private func autoActivateMaps() {
        let savedActive = mapState.activeDynamicOverlays

        // First launch: don't activate anything automatically
        guard !savedActive.isEmpty else { return }

        for map in offlineMaps.availableMaps {
            guard savedActive.contains(map.id) else { continue }

            if let url = offlineMaps.activate(map.id) {
                mapState.dynamicOfflineLayers[map.id] = url

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
