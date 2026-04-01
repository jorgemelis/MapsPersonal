import CoreLocation

/// Simplified 1D Kalman filter applied independently to latitude and longitude.
/// Smooths GPS noise for polyline visualization while preserving raw data in GPX.
struct KalmanGPSFilter {
    private var latEstimate: Double?
    private var lonEstimate: Double?
    private var latVariance: Double = 0
    private var lonVariance: Double = 0
    private var lastTimestamp: Date?
    private var lastSpeed: Double = 0

    /// Process noise per second (m²/s). Higher = trusts GPS more, lower = smoother.
    /// Tuned for walking (~1.4 m/s): allows ~3m deviation per second.
    private let processNoisePerSecond: Double = 9.0

    /// Minimum measurement noise (m²). Prevents over-smoothing when GPS is very accurate.
    private let minMeasurementNoise: Double = 4.0

    /// Filter a raw GPS location and return a smoothed coordinate.
    mutating func filter(_ location: CLLocation) -> CLLocationCoordinate2D {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude

        // Measurement noise R from GPS accuracy (in degrees²)
        let accuracyM = max(location.horizontalAccuracy, sqrt(minMeasurementNoise))
        let rLat = metersToDegreesLat(accuracyM) * metersToDegreesLat(accuracyM)
        let rLon = metersToDegreesLon(accuracyM, atLat: lat) * metersToDegreesLon(accuracyM, atLat: lat)

        guard let prevLat = latEstimate, let prevLon = lonEstimate, let prevTime = lastTimestamp else {
            // First point: initialize state
            latEstimate = lat
            lonEstimate = lon
            latVariance = rLat
            lonVariance = rLon
            lastTimestamp = location.timestamp
            lastSpeed = location.speed >= 0 ? location.speed : 0
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }

        let dt = max(location.timestamp.timeIntervalSince(prevTime), 0.1)

        // Process noise Q scales with time and speed
        let speed = location.speed >= 0 ? location.speed : lastSpeed
        let qFactor = processNoisePerSecond * dt * max(speed / 1.4, 0.5)
        let qLat = metersToDegreesLat(sqrt(qFactor)) * metersToDegreesLat(sqrt(qFactor))
        let qLon = metersToDegreesLon(sqrt(qFactor), atLat: lat) * metersToDegreesLon(sqrt(qFactor), atLat: lat)

        // --- PREDICT ---
        // Simple constant-position model (no velocity prediction to keep it simple)
        let predLat = prevLat
        let predLon = prevLon
        let predVarLat = latVariance + qLat
        let predVarLon = lonVariance + qLon

        // --- CORRECT ---
        let kLat = predVarLat / (predVarLat + rLat)
        let kLon = predVarLon / (predVarLon + rLon)

        let newLat = predLat + kLat * (lat - predLat)
        let newLon = predLon + kLon * (lon - predLon)

        latEstimate = newLat
        lonEstimate = newLon
        latVariance = (1 - kLat) * predVarLat
        lonVariance = (1 - kLon) * predVarLon
        lastTimestamp = location.timestamp
        lastSpeed = speed

        return CLLocationCoordinate2D(latitude: newLat, longitude: newLon)
    }

    /// Reset filter state (e.g., when starting a new recording)
    mutating func reset() {
        latEstimate = nil
        lonEstimate = nil
        latVariance = 0
        lonVariance = 0
        lastTimestamp = nil
        lastSpeed = 0
    }

    // MARK: - Unit conversions

    /// Convert meters to approximate degrees latitude
    private func metersToDegreesLat(_ meters: Double) -> Double {
        meters / 111_320.0
    }

    /// Convert meters to approximate degrees longitude at a given latitude
    private func metersToDegreesLon(_ meters: Double, atLat lat: Double) -> Double {
        let cosLat = cos(lat * .pi / 180.0)
        guard cosLat > 0.001 else { return meters / 111_320.0 }
        return meters / (111_320.0 * cosLat)
    }
}
