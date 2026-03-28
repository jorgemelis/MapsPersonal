import Foundation
import CoreLocation

// MARK: - Track Recorder

@Observable
class TrackRecorder {
    private let locationService: LocationService
    let heartRateService = HeartRateService()

    var isRecording = false
    var currentTrack: GPXTrack?
    var pointCount: Int { currentTrack?.points.count ?? 0 }
    var totalDistance: CLLocationDistance { currentTrack?.totalDistance ?? 0 }
    var duration: TimeInterval { currentTrack?.duration ?? 0 }

    private let minAccuracy: CLLocationDistance = 30 // discard points with accuracy > 30m

    init(locationService: LocationService) {
        self.locationService = locationService
    }

    func startRecording() {
        currentTrack = GPXTrack()
        isRecording = true
        locationService.enableRecordingMode()

        // Request HealthKit permission and start HR monitoring
        if heartRateService.isAvailable {
            Task {
                if !heartRateService.isAuthorized {
                    await heartRateService.requestAuthorization()
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
    }

    func saveTrack() -> GPXTrack? {
        guard let track = currentTrack, !track.points.isEmpty else { return nil }

        // Export to GPX file in Documents
        let gpxString = GPXExporter.export(track: track)
        let fileName = "\(track.name).gpx"

        if let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = docsURL.appendingPathComponent(fileName)
            try? gpxString.write(to: fileURL, atomically: true, encoding: .utf8)
            lastSavedFileURL = fileURL
        }

        let saved = track
        currentTrack = nil
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
            return false
        }
        let tracksDir = container.appendingPathComponent("Documents/Tracks")
        let fm = FileManager.default
        if !fm.fileExists(atPath: tracksDir.path) {
            try? fm.createDirectory(at: tracksDir, withIntermediateDirectories: true)
        }
        let dest = tracksDir.appendingPathComponent(url.lastPathComponent)
        if fm.fileExists(atPath: dest.path) {
            try? fm.removeItem(at: dest)
        }
        do {
            try fm.copyItem(at: url, to: dest)
            return true
        } catch {
            return false
        }
    }

    func discardTrack() {
        stopRecording()
        currentTrack = nil
    }

    private func addPoint(_ location: CLLocation) {
        guard isRecording else { return }
        guard location.horizontalAccuracy <= minAccuracy else { return }
        guard location.horizontalAccuracy >= 0 else { return }

        let point = TrackPoint(location: location, heartRate: heartRateService.currentHeartRate)
        currentTrack?.points.append(point)
    }
}
