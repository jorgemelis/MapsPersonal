import Foundation
import CoreLocation

// MARK: - Track Recorder

@Observable
class TrackRecorder {
    private let locationService: LocationService

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

        locationService.onLocationUpdate = { [weak self] location in
            self?.addPoint(location)
        }
    }

    func stopRecording() {
        isRecording = false
        locationService.disableRecordingMode()
        locationService.onLocationUpdate = nil
    }

    func saveTrack() -> GPXTrack? {
        guard let track = currentTrack, !track.points.isEmpty else { return nil }

        // Export to GPX file
        let gpxString = GPXExporter.export(track: track)
        let fileName = "\(track.name).gpx"

        if let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = docsURL.appendingPathComponent(fileName)
            try? gpxString.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        let saved = track
        currentTrack = nil
        return saved
    }

    func discardTrack() {
        stopRecording()
        currentTrack = nil
    }

    private func addPoint(_ location: CLLocation) {
        guard isRecording else { return }
        guard location.horizontalAccuracy <= minAccuracy else { return }
        guard location.horizontalAccuracy >= 0 else { return }

        let point = TrackPoint(location: location)
        currentTrack?.points.append(point)
    }
}
