import Foundation
import CoreLocation
import UIKit

// MARK: - Track Point

struct TrackPoint: Codable, Identifiable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let elevation: Double?
    let timestamp: Date
    var heartRate: Int?
    /// Temperature in °C from Open-Meteo weather model (forecast, not measured)
    var temperature: Double?
    /// Humidity in % from Open-Meteo weather model (forecast)
    var forecastHumidity: Double?
    /// Surface pressure in hPa from Open-Meteo weather model (forecast)
    var forecastPressure: Double?
    /// Measured temperature in °C from RuuviTag sensor
    var measuredTemperature: Double?
    /// Measured relative humidity in % from RuuviTag sensor
    var humidity: Double?
    /// Measured atmospheric pressure in hPa from RuuviTag sensor
    var pressure: Double?

    init(location: CLLocation, heartRate: Int? = nil, temperature: Double? = nil,
         forecastHumidity: Double? = nil, forecastPressure: Double? = nil,
         measuredTemperature: Double? = nil, humidity: Double? = nil, pressure: Double? = nil) {
        self.id = UUID()
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.elevation = location.altitude > -999 ? location.altitude : nil
        self.timestamp = location.timestamp
        self.heartRate = heartRate
        self.temperature = temperature
        self.forecastHumidity = forecastHumidity
        self.forecastPressure = forecastPressure
        self.measuredTemperature = measuredTemperature
        self.humidity = humidity
        self.pressure = pressure
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - GPX Track

struct GPXTrack: Identifiable, Codable {
    let id: UUID
    let name: String
    let startDate: Date
    var points: [TrackPoint]

    init(name: String? = nil) {
        self.id = UUID()
        self.startDate = Date()
        self.name = name ?? Self.defaultName(for: Date())
        self.points = []
    }

    /// Init from parsed GPX data
    init(name: String, startDate: Date, points: [TrackPoint]) {
        self.id = UUID()
        self.name = name
        self.startDate = startDate
        self.points = points
    }

    var totalDistance: CLLocationDistance {
        guard points.count > 1 else { return 0 }
        var distance: CLLocationDistance = 0
        for i in 1..<points.count {
            let prev = CLLocation(latitude: points[i-1].latitude, longitude: points[i-1].longitude)
            let curr = CLLocation(latitude: points[i].latitude, longitude: points[i].longitude)
            distance += curr.distance(from: prev)
        }
        return distance
    }

    var duration: TimeInterval {
        guard let first = points.first, let last = points.last else { return 0 }
        return last.timestamp.timeIntervalSince(first.timestamp)
    }

    var coordinates: [CLLocationCoordinate2D] {
        points.map { $0.coordinate }
    }

    // MARK: - Altitude stats

    var minElevation: Double? {
        points.compactMap { $0.elevation }.min()
    }

    var maxElevation: Double? {
        points.compactMap { $0.elevation }.max()
    }

    var elevationGain: Double {
        guard points.count > 1 else { return 0 }
        var gain: Double = 0
        var prevEle: Double?
        for point in points {
            guard let ele = point.elevation else { continue }
            if let prev = prevEle, ele > prev {
                gain += ele - prev
            }
            prevEle = ele
        }
        return gain
    }

    var elevationLoss: Double {
        guard points.count > 1 else { return 0 }
        var loss: Double = 0
        var prevEle: Double?
        for point in points {
            guard let ele = point.elevation else { continue }
            if let prev = prevEle, ele < prev {
                loss += prev - ele
            }
            prevEle = ele
        }
        return loss
    }

    var currentElevation: Double? {
        points.last?.elevation
    }

    // MARK: - Speed & movement stats

    /// Average speed in m/s (total distance / total time)
    var averageSpeed: Double {
        guard duration > 0 else { return 0 }
        return totalDistance / duration
    }

    /// Time spent moving (speed > 0.5 km/h threshold)
    var movingTime: TimeInterval {
        guard points.count > 1 else { return 0 }
        var moving: TimeInterval = 0
        let threshold: Double = 0.14 // ~0.5 km/h in m/s
        for i in 1..<points.count {
            let prev = CLLocation(latitude: points[i-1].latitude, longitude: points[i-1].longitude)
            let curr = CLLocation(latitude: points[i].latitude, longitude: points[i].longitude)
            let dt = points[i].timestamp.timeIntervalSince(points[i-1].timestamp)
            guard dt > 0 else { continue }
            let speed = curr.distance(from: prev) / dt
            if speed > threshold {
                moving += dt
            }
        }
        return moving
    }

    /// Average moving speed in m/s
    var averageMovingSpeed: Double {
        guard movingTime > 0 else { return 0 }
        return totalDistance / movingTime
    }

    /// Stopped time
    var stoppedTime: TimeInterval {
        duration - movingTime
    }

    // MARK: - Heart Rate stats

    var averageHeartRate: Int? {
        let hrs = points.compactMap { $0.heartRate }
        guard !hrs.isEmpty else { return nil }
        return hrs.reduce(0, +) / hrs.count
    }

    var maxHeartRate: Int? {
        points.compactMap { $0.heartRate }.max()
    }

    var hasHeartRate: Bool {
        points.contains { $0.heartRate != nil }
    }

    var hasSensorData: Bool {
        points.contains { $0.measuredTemperature != nil }
    }

    // MARK: - Cumulative Distances

    /// Cumulative distances at each point (in meters)
    var cumulativeDistances: [Double] {
        guard points.count > 0 else { return [] }
        var dists = [0.0]
        for i in 1..<points.count {
            let prev = CLLocation(latitude: points[i-1].latitude, longitude: points[i-1].longitude)
            let curr = CLLocation(latitude: points[i].latitude, longitude: points[i].longitude)
            dists.append(dists[i-1] + curr.distance(from: prev))
        }
        return dists
    }

    // MARK: - Smoothed Elevation Profile

    /// Elevation profile smoothed with moving average, paired with distance
    var elevationProfile: [(distance: Double, elevation: Double)] {
        let cumDist = cumulativeDistances
        guard cumDist.count == points.count else { return [] }

        // Build raw elevation array, interpolating missing values
        var raw: [Double] = []
        var lastEle: Double = 0
        for p in points {
            if let ele = p.elevation {
                lastEle = ele
            }
            raw.append(lastEle)
        }

        guard raw.count > 2 else {
            return raw.enumerated().map { (cumDist[$0], $1) }
        }

        // Smooth with moving average (window=25)
        let window = min(25, raw.count)
        var result: [(distance: Double, elevation: Double)] = []
        result.reserveCapacity(raw.count)
        for i in 0..<raw.count {
            let half = window / 2
            let lo = max(0, i - half)
            let hi = min(raw.count - 1, i + half)
            let slice = raw[lo...hi]
            let avg = slice.reduce(0, +) / Double(slice.count)
            result.append((distance: cumDist[i], elevation: avg))
        }
        return result
    }

    // MARK: - Heart Rate Profile

    /// Heart rate paired with distance, smoothed with moving average (window=15)
    var heartRateProfile: [(distance: Double, hr: Int)] {
        let cumDist = cumulativeDistances
        guard cumDist.count == points.count else { return [] }

        // Collect raw HR values with their distances
        var raw: [(distance: Double, hr: Double)] = []
        for (i, p) in points.enumerated() {
            if let hr = p.heartRate {
                raw.append((distance: cumDist[i], hr: Double(hr)))
            }
        }
        guard raw.count > 2 else { return raw.map { ($0.distance, Int($0.hr)) } }

        // Smooth with moving average (window=15)
        let window = min(15, raw.count)
        var result: [(distance: Double, hr: Int)] = []
        result.reserveCapacity(raw.count)
        for i in 0..<raw.count {
            let half = window / 2
            let lo = max(0, i - half)
            let hi = min(raw.count - 1, i + half)
            let slice = raw[lo...hi]
            let avg = slice.map(\.hr).reduce(0, +) / Double(slice.count)
            result.append((distance: raw[i].distance, hr: Int(avg)))
        }
        return result
    }

    // MARK: - Splits per km

    struct Split: Identifiable {
        let id: Int      // km number (1-indexed)
        let km: Int
        let pace: TimeInterval  // seconds per km (moving time only)
        let elevationChange: Double
        let isPartial: Bool
        let partialMeters: Double  // actual meters if partial
    }

    var splits: [Split] {
        guard points.count > 1 else { return [] }
        let cumDist = cumulativeDistances
        let threshold: Double = 0.14

        var result: [Split] = []
        var kmStart = 0
        var currentKm = 1
        var movingTime: TimeInterval = 0

        for i in 1..<points.count {
            let dt = points[i].timestamp.timeIntervalSince(points[i-1].timestamp)
            let segDist = cumDist[i] - cumDist[i-1]
            let speed = dt > 0 ? segDist / dt : 0
            if speed > threshold { movingTime += dt }

            let targetDist = Double(currentKm) * 1000.0
            if cumDist[i] >= targetDist {
                let startEle = points[kmStart].elevation ?? 0
                let endEle = points[i].elevation ?? 0
                result.append(Split(
                    id: currentKm,
                    km: currentKm,
                    pace: movingTime,
                    elevationChange: endEle - startEle,
                    isPartial: false,
                    partialMeters: 1000
                ))
                currentKm += 1
                kmStart = i
                movingTime = 0
            }
        }

        // Final partial km (only if > 100m)
        let remaining = cumDist.last! - Double(currentKm - 1) * 1000.0
        if remaining > 100 {
            let startEle = points[kmStart].elevation ?? 0
            let endEle = points.last?.elevation ?? 0
            // Scale pace to per-km equivalent
            let scaledPace = remaining > 0 ? movingTime / remaining * 1000 : 0
            result.append(Split(
                id: currentKm,
                km: currentKm,
                pace: scaledPace,
                elevationChange: endEle - startEle,
                isPartial: true,
                partialMeters: remaining
            ))
        }

        return result
    }

    // MARK: - Speed profile (smoothed, km/h)

    /// Per-segment speeds in km/h, smoothed with moving average
    var smoothedSpeeds: [(distance: Double, speed: Double)] {
        guard points.count > 2 else { return [] }
        let cumDist = cumulativeDistances
        var rawSpeeds: [Double] = [0]
        for i in 1..<points.count {
            let dt = points[i].timestamp.timeIntervalSince(points[i-1].timestamp)
            let dist = cumDist[i] - cumDist[i-1]
            rawSpeeds.append(dt > 0 ? (dist / dt) * 3.6 : 0)
        }

        // Moving average (window=15)
        let window = min(15, rawSpeeds.count)
        var result: [(distance: Double, speed: Double)] = []
        for i in 0..<rawSpeeds.count {
            let half = window / 2
            let lo = max(0, i - half)
            let hi = min(rawSpeeds.count - 1, i + half)
            let avg = rawSpeeds[lo...hi].reduce(0, +) / Double(hi - lo + 1)
            result.append((distance: cumDist[i], speed: avg))
        }
        return result
    }

    private static func defaultName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        return "MP\(formatter.string(from: date))_\(device)"
    }
}
