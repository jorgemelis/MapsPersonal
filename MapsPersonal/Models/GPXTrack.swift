import Foundation
import CoreLocation

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

    init(location: CLLocation, heartRate: Int? = nil, temperature: Double? = nil) {
        self.id = UUID()
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.elevation = location.altitude > -999 ? location.altitude : nil
        self.timestamp = location.timestamp
        self.heartRate = heartRate
        self.temperature = temperature
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

    private static func defaultName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"
        return "MP\(formatter.string(from: date))"
    }
}
