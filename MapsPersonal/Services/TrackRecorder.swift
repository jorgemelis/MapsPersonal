import Foundation
import CoreLocation

extension Notification.Name {
    static let trackPointAdded = Notification.Name("trackPointAdded")
}

// MARK: - Track Recorder

@Observable
class TrackRecorder {
    private let locationService: LocationService
    let heartRateService = HeartRateService()

    var isRecording = false
    var currentTrack: GPXTrack?
    var trackVersion = 0  // increments on each new point, triggers map redraw

    /// Kalman-filtered coordinates for smooth polyline visualization
    var smoothedCoordinates: [CLLocationCoordinate2D] = []
    private var kalmanFilter = KalmanGPSFilter()
    var pointCount: Int { currentTrack?.points.count ?? 0 }
    var totalDistance: CLLocationDistance { currentTrack?.totalDistance ?? 0 }
    var duration: TimeInterval { currentTrack?.duration ?? 0 }

    /// Current temperature from weather model (for display in stats bar)
    var currentTemperature: Double?

    /// Whether a RuuviTag sensor is currently connected (for UI indicator)
    var isRuuviTagConnected: Bool { ruuviTagService?.isConnected ?? false }

    /// HR zone time distribution (seconds per zone, 0-indexed)
    var zoneTimeDistribution: [TimeInterval] = Array(repeating: 0, count: 5)
    /// Current HR zone index (0-based, nil if no HR or no profile)
    var currentZoneIndex: Int?

    private var userProfile: UserProfile?
    private var lastZoneUpdateTime: Date?

    private let minAccuracy: CLLocationDistance = 30 // discard points with accuracy > 30m
    private let autoSaveInterval = 50 // auto-save recovery file every N points
    private static let recoveryFileName = "track_recovery.json"

    // Temperature recording triggers (read from UserProfile, with fallback defaults)
    private var tempTimeInterval: TimeInterval {
        guard let profile = userProfile else { return 300 }
        return TimeInterval(profile.tempIntervalMinutes * 60)
    }
    private var tempElevationThreshold: Double {
        guard let profile = userProfile else { return 100 }
        return Double(profile.tempElevationThreshold)
    }
    private var lastTempFetchTime: Date?
    private var lastTempElevation: Double?
    private var cumulativeElevationChange: Double = 0
    private var weatherService: WeatherService?
    private var ruuviTagService: RuuviTagService?

    init(locationService: LocationService) {
        self.locationService = locationService
    }

    /// Set the weather service to enable temperature recording
    func setWeatherService(_ service: WeatherService) {
        self.weatherService = service
    }

    /// Set the RuuviTag service to enable measured sensor data recording
    func setRuuviTagService(_ service: RuuviTagService) {
        self.ruuviTagService = service
    }

    /// Set the user profile for HR zone tracking
    func setUserProfile(_ profile: UserProfile) {
        self.userProfile = profile
    }

    func startRecording() {
        currentTrack = GPXTrack()
        isRecording = true
        locationService.enableRecordingMode()

        // Reset Kalman filter and smoothed coordinates
        kalmanFilter.reset()
        smoothedCoordinates = []

        // Reset temperature tracking state
        lastTempFetchTime = nil
        lastTempElevation = nil
        cumulativeElevationChange = 0
        currentTemperature = weatherService?.temperature

        // Reset HR zone tracking
        zoneTimeDistribution = Array(repeating: 0, count: userProfile?.zones.count ?? 5)
        currentZoneIndex = nil
        lastZoneUpdateTime = nil

        // Start RuuviTag BLE scanning if service is configured
        ruuviTagService?.startScanning()

        // Request HealthKit permission and start HR monitoring
        if heartRateService.isAvailable {
            Task {
                if !heartRateService.isAuthorized {
                    _ = await heartRateService.requestAuthorization()
                }
                heartRateService.startMonitoring()
            }
        }

        locationService.onLocationUpdate = { [weak self] location in
            self?.addPoint(location)
        }
    }

    func stopRecording() {
        isRecording = false
        locationService.disableRecordingMode()
        locationService.onLocationUpdate = nil
        heartRateService.stopMonitoring()
        ruuviTagService?.stopScanning()

        // Save recovery snapshot when stopping (in case user doesn't save immediately)
        if let track = currentTrack, !track.points.isEmpty {
            saveRecoveryFile(track)
        }
    }

    func saveTrack() -> GPXTrack? {
        guard let track = currentTrack, !track.points.isEmpty else { return nil }

        // Build HR zone export data if available
        var hrZoneData: HRZoneExportData?
        if let profile = userProfile, let maxHR = profile.maxHR {
            hrZoneData = HRZoneExportData(
                maxHR: maxHR,
                zones: profile.zones,
                timeDistribution: zoneTimeDistribution
            )
        }

        // Export to GPX file in Documents
        let gpxString = GPXExporter.export(track: track, hrZones: hrZoneData)
        let fileName = "\(track.name).gpx"

        if let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = docsURL.appendingPathComponent(fileName)
            try? gpxString.write(to: fileURL, atomically: true, encoding: .utf8)
            lastSavedFileURL = fileURL

            // Auto-save to iCloud if enabled
            if userProfile?.autoSaveICloud == true {
                let copied = Self.copyToICloud(fileURL)
                print("TrackRecorder: iCloud auto-save \(copied ? "OK" : "FAILED") for \(fileName)")
            }
        }

        // Save workout to HealthKit (async, fire-and-forget)
        if let first = track.points.first, let last = track.points.last {
            let distance = track.totalDistance
            let elevGain = track.elevationGain
            Task {
                await heartRateService.saveWorkout(
                    start: first.timestamp,
                    end: last.timestamp,
                    distance: distance,
                    elevationGain: elevGain
                )
            }
        }

        let saved = track
        currentTrack = nil
        smoothedCoordinates = []
        Self.deleteRecoveryFile()
        return saved
    }

    /// URL of the last saved GPX file (for sharing)
    var lastSavedFileURL: URL?

    /// List all saved GPX files in Documents
    static func savedFiles() -> [URL] {
        guard let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(at: docsURL, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "gpx" }
            .sorted { ($0.lastPathComponent) > ($1.lastPathComponent) }
    }

    /// Delete a saved GPX file
    static func deleteFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Copy a GPX file to iCloud for access from Mac/iPad
    static func copyToICloud(_ url: URL) -> Bool {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.jorge.mapspersonal2026") else {
            print("TrackRecorder: iCloud container NOT available (user not signed in or iCloud Drive disabled)")
            return false
        }
        let tracksDir = container.appendingPathComponent("Documents/Tracks")
        let fm = FileManager.default
        if !fm.fileExists(atPath: tracksDir.path) {
            do {
                try fm.createDirectory(at: tracksDir, withIntermediateDirectories: true)
            } catch {
                print("TrackRecorder: failed to create iCloud Tracks dir: \(error)")
                return false
            }
        }
        let dest = tracksDir.appendingPathComponent(url.lastPathComponent)
        if fm.fileExists(atPath: dest.path) {
            try? fm.removeItem(at: dest)
        }
        do {
            try fm.copyItem(at: url, to: dest)
            return true
        } catch {
            print("TrackRecorder: iCloud copy failed: \(error)")
            return false
        }
    }

    func discardTrack() {
        stopRecording()
        currentTrack = nil
        smoothedCoordinates = []
        Self.deleteRecoveryFile()
    }

    private func addPoint(_ location: CLLocation) {
        guard isRecording else { return }
        guard location.horizontalAccuracy <= minAccuracy else { return }
        guard location.horizontalAccuracy >= 0 else { return }

        // Check if we should fetch a new weather reading
        let shouldFetch = shouldFetchTemperature(elevation: location.altitude)
        let temp = shouldFetch ? weatherService?.temperature : nil
        let forecastHum = shouldFetch ? weatherService?.humidity.map { Double($0) } : nil
        let forecastPres = shouldFetch ? weatherService?.pressure : nil

        if let temp {
            currentTemperature = temp
        }

        // Track cumulative elevation change for temperature triggers
        updateElevationTracking(elevation: location.altitude)

        // Update HR zone time tracking
        let hr = heartRateService.currentHeartRate
        updateZoneTracking(heartRate: hr, at: location.timestamp)

        // Capture RuuviTag sensor data if available
        let measuredTemp = ruuviTagService?.isConnected == true ? ruuviTagService?.temperature : nil
        let measuredHumidity = ruuviTagService?.isConnected == true ? ruuviTagService?.humidity : nil
        let measuredPressure = ruuviTagService?.isConnected == true ? ruuviTagService?.pressure : nil

        let point = TrackPoint(
            location: location,
            heartRate: hr,
            temperature: temp,
            forecastHumidity: forecastHum,
            forecastPressure: forecastPres,
            measuredTemperature: measuredTemp,
            humidity: measuredHumidity,
            pressure: measuredPressure
        )
        currentTrack?.points.append(point)

        // Kalman-filtered coordinate for smooth polyline display
        let smoothed = kalmanFilter.filter(location)
        smoothedCoordinates.append(smoothed)

        trackVersion += 1
        NotificationCenter.default.post(name: .trackPointAdded, object: self)

        // Auto-save recovery file periodically
        if let track = currentTrack, track.points.count % autoSaveInterval == 0 {
            saveRecoveryFile(track)
        }
    }

    // MARK: - Recovery (auto-save)

    private func saveRecoveryFile(_ track: GPXTrack) {
        guard let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let fileURL = docsURL.appendingPathComponent(Self.recoveryFileName)
        do {
            let data = try JSONEncoder().encode(track)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("TrackRecorder: recovery save failed: \(error)")
        }
    }

    static func deleteRecoveryFile() {
        guard let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let fileURL = docsURL.appendingPathComponent(recoveryFileName)
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Check if a recovery file exists and load the track from it
    static func loadRecoveryTrack() -> GPXTrack? {
        guard let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let fileURL = docsURL.appendingPathComponent(recoveryFileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(GPXTrack.self, from: data)
        } catch {
            print("TrackRecorder: recovery load failed: \(error)")
            return nil
        }
    }

    /// Accumulate time spent in each HR zone
    private func updateZoneTracking(heartRate: Int?, at timestamp: Date) {
        defer { lastZoneUpdateTime = timestamp }

        guard let hr = heartRate,
              let profile = userProfile,
              let zoneInfo = profile.zone(for: hr) else {
            currentZoneIndex = nil
            return
        }

        currentZoneIndex = zoneInfo.index

        // Accumulate time since last update to the current zone
        if let lastTime = lastZoneUpdateTime {
            let dt = timestamp.timeIntervalSince(lastTime)
            if dt > 0, dt < 60, zoneInfo.index < zoneTimeDistribution.count {
                zoneTimeDistribution[zoneInfo.index] += dt
            }
        }
    }

    /// Determine if we should record temperature on this point
    private func shouldFetchTemperature(elevation: Double) -> Bool {
        let now = Date()

        // First point always gets temperature
        guard let lastFetch = lastTempFetchTime else {
            lastTempFetchTime = now
            lastTempElevation = elevation > -999 ? elevation : nil
            return true
        }

        // Time trigger: every 5 minutes
        if now.timeIntervalSince(lastFetch) >= tempTimeInterval {
            lastTempFetchTime = now
            lastTempElevation = elevation > -999 ? elevation : nil
            cumulativeElevationChange = 0
            return true
        }

        // Elevation trigger: 100m cumulative change
        if cumulativeElevationChange >= tempElevationThreshold {
            lastTempFetchTime = now
            lastTempElevation = elevation > -999 ? elevation : nil
            cumulativeElevationChange = 0
            return true
        }

        return false
    }

    /// Track cumulative elevation change between temperature readings
    private func updateElevationTracking(elevation: Double) {
        guard elevation > -999 else { return }
        if let lastEle = lastTempElevation {
            cumulativeElevationChange += abs(elevation - lastEle)
        }
        lastTempElevation = elevation
    }
}
