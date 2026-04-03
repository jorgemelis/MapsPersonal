import SwiftUI
import CoreLocation

// MARK: - Content View

struct ContentView: View {
    @State private var mapState = MapState()
    @State private var locationService = LocationService()
    @State private var trackRecorder: TrackRecorder?
    @State private var offlineMaps = OfflineMapsManager()
    @State private var weather = WeatherService()
    @State private var userProfile = UserProfile()
    @State private var showLayerPicker = false
    // showOfflineMaps removed — offline maps now in LayerPickerView
    @State private var showStats = false
    @State private var showWeather = false
    @State private var showTrackManager = false
    @State private var showSettings = false
    @State private var showChecklists = false
    @State private var showLegends = false
    @State private var showHelp = false
    @State private var shareFileURL: URL?
    @State private var showSaveConfirmation = false
    @State private var coordinateText = ""
    @State private var mapBearing: Double = 0
    @State private var mapPitch: Double = 0
    @State private var tractive = TractiveService()
    @State private var ruuviTag = RuuviTagService()
    @State private var peakService = PeakService()
    @State private var showSearch = false
    @State private var searchText = ""
    @State private var searchResults: [GeocodingResult] = []
    @State private var isSearching = false
    @State private var showRecoveryAlert = false
    @State private var recoveredTrack: GPXTrack?

    var body: some View {
        ZStack {
            // Map
            MapViewRepresentable(
                mapState: mapState,
                trackRecorder: trackRecorder ?? TrackRecorder(locationService: locationService),
                tractiveService: tractive.isConnected ? tractive : nil,
                peakService: mapState.showPeaks ? peakService : nil,
                onCameraChange: { coord, zoom, bearing, pitch in
                    DispatchQueue.main.async {
                        coordinateText = String(format: "%.5f, %.5f  z%.1f", coord.latitude, coord.longitude, zoom)
                        mapBearing = bearing
                        mapPitch = pitch
                    }
                },
                terrainVersion: mapState.terrainVersion,
                trackVersion: trackRecorder?.trackVersion ?? 0,
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

            // Search overlay
            if showSearch {
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search place...", text: $searchText)
                            .textFieldStyle(.plain)
                            .autocorrectionDisabled()
                            .onSubmit { performSearch() }
                        if isSearching {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Button {
                            showSearch = false
                            searchText = ""
                            searchResults = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                    .padding(.top, 50)

                    if !searchResults.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(searchResults) { result in
                                Button {
                                    mapState.flyToCoordinate = result.coordinate
                                    showSearch = false
                                    searchText = ""
                                    searchResults = []
                                } label: {
                                    HStack {
                                        Image(systemName: "mappin")
                                            .foregroundStyle(.red)
                                            .frame(width: 20)
                                        Text(result.name)
                                            .font(.subheadline)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                }
                                Divider()
                            }
                        }
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal)
                        .padding(.top, 4)
                    }

                    Spacer()
                }
                .zIndex(10)
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
                            // Auto-save immediately on stop
                            if let track = recorder.saveTrack() {
                                mapState.savedTracks.append(track)
                                showSaveConfirmation = true
                            }
                            showStats = false
                        },
                        onDiscard: {
                            // Delete the already-saved GPX file, then discard
                            if let url = recorder.lastSavedFileURL {
                                TrackRecorder.deleteFile(at: url)
                            }
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
                HStack(spacing: 0) {
                    // Weather toggle
                    if weather.temperature != nil {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showWeather.toggle()
                            }
                        } label: {
                            Image(systemName: showWeather ? "cloud.sun.fill" : "cloud.sun")
                                .font(.body)
                                .padding(7)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .frame(maxWidth: .infinity)
                    }

                    // Pet tracker menu
                    if tractive.isConnected {
                        Menu {
                            ForEach(tractive.pets) { pet in
                                Section(pet.emoji + " " + pet.name + (pet.batteryLevel.map { " \($0)%" } ?? "")) {
                                    Button {
                                        tractive.togglePet(pet.id)
                                    } label: {
                                        Label("Mostrar en mapa", systemImage: pet.isVisible ? "checkmark.circle.fill" : "circle")
                                    }
                                    Button {
                                        Task { await tractive.toggleLiveTracking(pet.id) }
                                    } label: {
                                        Label(
                                            pet.isLive ? "LIVE activado" : "Activar LIVE",
                                            systemImage: pet.isLive ? "antenna.radiowaves.left.and.right.circle.fill" : "antenna.radiowaves.left.and.right"
                                        )
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "pawprint.fill")
                                .font(.body)
                                .padding(7)
                                .background(
                                    tractive.pets.contains(where: { $0.isLive })
                                        ? AnyShapeStyle(.green.opacity(0.4))
                                        : tractive.visiblePets.isEmpty
                                            ? AnyShapeStyle(.ultraThinMaterial)
                                            : AnyShapeStyle(.orange.opacity(0.3)),
                                    in: Circle()
                                )
                        }
                        .frame(maxWidth: .infinity)
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
                                .font(.body)
                                .foregroundStyle(.red)
                                .padding(7)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .frame(maxWidth: .infinity)
                    }

                    // Search
                    Button {
                        withAnimation { showSearch.toggle() }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.body)
                            .padding(7)
                            .background(showSearch ? AnyShapeStyle(.blue.opacity(0.3)) : AnyShapeStyle(.ultraThinMaterial), in: Circle())
                    }
                    .frame(maxWidth: .infinity)

                    // Location: tap = toggle follow mode
                    Button {
                        mapState.isFollowingUser.toggle()
                    } label: {
                        Image(systemName: mapState.isFollowingUser ? "location.fill" : "location")
                            .font(.body)
                            .padding(7)
                            .background(mapState.isFollowingUser ? AnyShapeStyle(.blue.opacity(0.3)) : AnyShapeStyle(.ultraThinMaterial), in: Circle())
                    }
                    .frame(maxWidth: .infinity)

                    // Layer picker
                    Button {
                        showLayerPicker = true
                    } label: {
                        Image(systemName: "square.3.layers.3d")
                            .font(.body)
                            .padding(7)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .frame(maxWidth: .infinity)

                    // More menu
                    Menu {
                        Button {
                            showTrackManager = true
                        } label: {
                            Label("Saved Tracks", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        }
                        Button {
                            showChecklists = true
                        } label: {
                            Label("Checklists", systemImage: "checklist")
                        }
                        Button {
                            showLegends = true
                        } label: {
                            Label("Leyendas", systemImage: "doc.richtext")
                        }
                        Divider()
                        Button {
                            showSettings = true
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                        Button {
                            showHelp = true
                        } label: {
                            Label("Features", systemImage: "questionmark.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.body)
                            .padding(7)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .frame(maxWidth: .infinity)
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
            trackRecorder?.setWeatherService(weather)
            trackRecorder?.setUserProfile(userProfile)
            trackRecorder?.setRuuviTagService(ruuviTag)
            ruuviTag.startScanning()
            locationService.requestAuthorization()
            offlineMaps.scan()
            autoActivateMaps()

            // Weather: fetch on first location, then every 10 min
            weather.startAutoRefresh {
                locationService.currentLocation?.coordinate
                    ?? (mapState.centerCoordinate.latitude != 40.4168 ? mapState.centerCoordinate : nil)
            }

            // Tractive: connect (starts event channel automatically)
            // Auto-refresh as fallback for when channel disconnects
            Task {
                await tractive.connect()
                if tractive.isConnected {
                    tractive.startAutoRefresh()
                }
            }

            // Check for unsaved track recovery
            if let track = TrackRecorder.loadRecoveryTrack() {
                recoveredTrack = track
                showRecoveryAlert = true
            }
        }
        .sheet(isPresented: $showLayerPicker) {
            LayerPickerView(
                mapState: mapState,
                offlineMaps: offlineMaps,
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
        .overlay {
            if showSaveConfirmation {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Track guardado")
                            .font(.subheadline.bold())
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 120)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { showSaveConfirmation = false }
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showSaveConfirmation)
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
        .sheet(isPresented: $showSettings) {
            SettingsView(tractive: tractive, mapState: mapState)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showChecklists) {
            ChecklistListView()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showLegends) {
            LegendView()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showHelp) {
            HelpView()
                .presentationDetents([.large])
        }
        .alert("Track sin guardar", isPresented: $showRecoveryAlert) {
            if canResumeRecoveredTrack {
                Button("Continuar grabando") {
                    if let track = recoveredTrack, let recorder = trackRecorder {
                        recorder.resumeRecording(from: track)
                        TrackRecorder.deleteRecoveryFile()
                    }
                    recoveredTrack = nil
                }
            }
            Button("Guardar") {
                if let track = recoveredTrack, let recorder = trackRecorder {
                    recorder.currentTrack = track
                    if let saved = recorder.saveTrack() {
                        mapState.savedTracks.append(saved)
                    }
                }
                recoveredTrack = nil
            }
            Button("Descartar", role: .destructive) {
                TrackRecorder.deleteRecoveryFile()
                recoveredTrack = nil
            }
        } message: {
            if let track = recoveredTrack {
                let elapsed = Int(Date().timeIntervalSince(track.points.last?.timestamp ?? track.startDate) / 60)
                if canResumeRecoveredTrack {
                    Text("Track con \(track.points.count) puntos, interrumpido hace \(elapsed) min. ¿Continuar grabando?")
                } else {
                    Text("Se encontró un track con \(track.points.count) puntos del \(track.startDate.formatted(date: .abbreviated, time: .shortened)).")
                }
            }
        }
    }

    /// Start tile servers only for maps that were explicitly active in previous session
    private func performSearch() {
        guard !searchText.isEmpty else { return }
        isSearching = true
        Task {
            let results = await GeocodingService.search(searchText)
            await MainActor.run {
                searchResults = results
                isSearching = false
            }
        }
    }

    private func autoActivateMaps() {
        let savedActive = mapState.activeDynamicOverlays

        // First launch: don't activate anything automatically
        guard !savedActive.isEmpty else { return }

        for map in offlineMaps.availableMaps {
            guard savedActive.contains(map.id) else { continue }

            if let url = offlineMaps.activate(map.id) {
                mapState.dynamicOfflineLayers[map.id] = url
            }
        }
    }

    /// Whether the recovered track is recent enough to resume (< 30 min gap, < 1km distance)
    private var canResumeRecoveredTrack: Bool {
        guard let track = recoveredTrack,
              let lastPoint = track.points.last else { return false }

        let elapsed = Date().timeIntervalSince(lastPoint.timestamp)
        guard elapsed < 30 * 60 else { return false }  // max 30 min gap

        // Check distance if we have current location
        if let currentLoc = locationService.currentLocation {
            let lastLoc = CLLocation(latitude: lastPoint.latitude, longitude: lastPoint.longitude)
            let distance = currentLoc.distance(from: lastLoc)
            guard distance < 1000 else { return false }  // max 1km away
        }

        return true
    }
}

#Preview {
    ContentView()
}
