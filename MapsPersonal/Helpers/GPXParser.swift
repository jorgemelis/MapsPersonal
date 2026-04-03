import Foundation
import CoreLocation

// MARK: - GPX Parser

/// Parses GPX 1.1 files exported by MapsPersonal, including custom mp: extensions.
enum GPXParser {

    /// Parse a GPX file at the given URL into a GPXTrack
    static func parse(url: URL) -> GPXTrack? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let delegate = GPXParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        guard parser.parse(), !delegate.points.isEmpty else { return nil }

        let name = delegate.trackName
            ?? url.deletingPathExtension().lastPathComponent
        let startDate = delegate.points.first?.timestamp ?? Date()

        return GPXTrack(
            name: name,
            startDate: startDate,
            points: delegate.points
        )
    }

    /// Parse all GPX files from the Documents directory, sorted newest first
    static func parseAll() -> [GPXTrack] {
        let files = TrackRecorder.savedFiles()
        return files.compactMap { parse(url: $0) }
    }
}

// MARK: - XML Parser Delegate

private class GPXParserDelegate: NSObject, XMLParserDelegate {
    var points: [TrackPoint] = []
    var trackName: String?

    // Current point being parsed
    private var currentLat: Double?
    private var currentLon: Double?
    private var currentEle: Double?
    private var currentTime: Date?
    private var currentHR: Int?
    private var currentForecastTemp: Double?
    private var currentForecastHumidity: Double?
    private var currentForecastPressure: Double?
    private var currentMeasuredTemp: Double?
    private var currentMeasuredHumidity: Double?
    private var currentMeasuredPressure: Double?

    // Parsing state
    private var currentText = ""
    private var inTrackPoint = false
    private var inExtensions = false
    private var inWeather = false
    private var inSensor = false
    private var inTrackPointExtension = false
    private var inTrackName = false

    private let iso = ISO8601DateFormatter()

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentText = ""

        switch elementName {
        case "trkpt":
            inTrackPoint = true
            currentLat = Double(attributes["lat"] ?? "")
            currentLon = Double(attributes["lon"] ?? "")
            resetPointFields()

        case "extensions" where inTrackPoint:
            inExtensions = true

        case "TrackPointExtension" where inExtensions:
            inTrackPointExtension = true

        case "weather" where inExtensions:
            inWeather = true

        case "sensor" where inExtensions:
            inSensor = true

        case "name" where !inTrackPoint:
            inTrackName = true

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "trkpt":
            if let lat = currentLat, let lon = currentLon, let time = currentTime {
                let location = CLLocation(
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    altitude: currentEle ?? -9999,
                    horizontalAccuracy: 0, verticalAccuracy: 0,
                    timestamp: time
                )
                let point = TrackPoint(
                    location: location,
                    heartRate: currentHR,
                    temperature: currentForecastTemp,
                    forecastHumidity: currentForecastHumidity,
                    forecastPressure: currentForecastPressure,
                    measuredTemperature: currentMeasuredTemp,
                    humidity: currentMeasuredHumidity,
                    pressure: currentMeasuredPressure
                )
                points.append(point)
            }
            inTrackPoint = false

        case "extensions" where inTrackPoint:
            inExtensions = false

        case "TrackPointExtension":
            inTrackPointExtension = false

        case "weather":
            inWeather = false

        case "sensor":
            inSensor = false

        case "ele" where inTrackPoint:
            currentEle = Double(text)

        case "time" where inTrackPoint:
            currentTime = iso.date(from: text)

        case "hr" where inTrackPointExtension:
            currentHR = Int(text)

        case "temp_c" where inWeather:
            currentForecastTemp = Double(text)

        case "humidity_pct" where inWeather:
            currentForecastHumidity = Double(text)

        case "pressure_hpa" where inWeather:
            currentForecastPressure = Double(text)

        case "temp_c" where inSensor:
            currentMeasuredTemp = Double(text)

        case "humidity_pct" where inSensor:
            currentMeasuredHumidity = Double(text)

        case "pressure_hpa" where inSensor:
            currentMeasuredPressure = Double(text)

        case "name" where inTrackName:
            if trackName == nil { trackName = text }
            inTrackName = false

        default:
            break
        }
    }

    private func resetPointFields() {
        currentEle = nil
        currentTime = nil
        currentHR = nil
        currentForecastTemp = nil
        currentForecastHumidity = nil
        currentForecastPressure = nil
        currentMeasuredTemp = nil
        currentMeasuredHumidity = nil
        currentMeasuredPressure = nil
    }
}
