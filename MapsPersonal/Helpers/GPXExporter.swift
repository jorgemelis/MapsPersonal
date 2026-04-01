import Foundation

// MARK: - GPX Exporter

/// HR zone distribution data for GPX export
struct HRZoneExportData {
    let maxHR: Int
    let zones: [HeartRateZone]
    let timeDistribution: [TimeInterval]
}

enum GPXExporter {
    static func export(track: GPXTrack, hrZones: HRZoneExportData? = nil) -> String {
        let iso = ISO8601DateFormatter()
        let hasHR = track.points.contains { $0.heartRate != nil }
        let hasTemp = track.points.contains { $0.temperature != nil || $0.forecastHumidity != nil || $0.forecastPressure != nil }
        let hasSensor = track.points.contains { $0.measuredTemperature != nil }
        let hasMPExtensions = hasTemp || hasSensor || hrZones != nil
        let hasExtensions = hasHR || hasTemp || hasSensor

        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="MapsPersonal"
             xmlns="http://www.topografix.com/GPX/1/1"
             xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        """

        if hasHR {
            gpx += "     xmlns:gpxtpx=\"http://www.garmin.com/xmlschemas/TrackPointExtension/v1\"\n"
        }
        if hasMPExtensions {
            gpx += "     xmlns:mp=\"http://mapspersonal.app/gpx/1\"\n"
        }
        gpx += "     xsi:schemaLocation=\"http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd\">\n"

        gpx += "  <metadata>\n"
        gpx += "    <name>\(escapeXML(track.name))</name>\n"
        gpx += "    <time>\(iso.string(from: track.startDate))</time>\n"
        if hasTemp || hasSensor {
            var descParts: [String] = []
            if hasTemp { descParts.append("mp:weather = Open-Meteo forecast") }
            if hasSensor { descParts.append("mp:sensor = RuuviTag measured") }
            gpx += "    <desc>Temperature sources: \(descParts.joined(separator: "; ")).</desc>\n"
        }
        gpx += "  </metadata>\n"
        gpx += "  <trk>\n"
        gpx += "    <name>\(escapeXML(track.name))</name>\n"

        // Track-level HR zone distribution
        if let zd = hrZones {
            let totalTime = zd.timeDistribution.reduce(0, +)
            if totalTime > 0 {
                gpx += "    <extensions>\n"
                gpx += "      <mp:hr_zones maxhr=\"\(zd.maxHR)\" formula=\"tanaka\">\n"
                for (i, zone) in zd.zones.enumerated() {
                    let secs = i < zd.timeDistribution.count ? zd.timeDistribution[i] : 0
                    let pct = secs / totalTime * 100
                    let range = zone.bpmRange(maxHR: zd.maxHR)
                    gpx += "        <mp:zone name=\"\(escapeXML(zone.name))\" min_bpm=\"\(range.lowerBound)\" max_bpm=\"\(range.upperBound)\" seconds=\"\(Int(secs))\" pct=\"\(String(format: "%.1f", pct))\"/>\n"
                }
                gpx += "      </mp:hr_zones>\n"
                gpx += "    </extensions>\n"
            }
        }

        gpx += "    <trkseg>\n"

        for point in track.points {
            gpx += "      <trkpt lat=\"\(point.latitude)\" lon=\"\(point.longitude)\">\n"
            if let ele = point.elevation {
                gpx += "        <ele>\(String(format: "%.1f", ele))</ele>\n"
            }
            gpx += "        <time>\(iso.string(from: point.timestamp))</time>\n"
            let hasPointExtensions = point.heartRate != nil || point.temperature != nil || point.forecastHumidity != nil || point.forecastPressure != nil || point.measuredTemperature != nil
            if hasExtensions && hasPointExtensions {
                gpx += "        <extensions>\n"
                if let hr = point.heartRate {
                    gpx += "          <gpxtpx:TrackPointExtension>\n"
                    gpx += "            <gpxtpx:hr>\(hr)</gpxtpx:hr>\n"
                    gpx += "          </gpxtpx:TrackPointExtension>\n"
                }
                if point.temperature != nil || point.forecastHumidity != nil || point.forecastPressure != nil {
                    gpx += "          <mp:weather source=\"open-meteo\" type=\"forecast\">\n"
                    if let temp = point.temperature {
                        gpx += "            <mp:temp_c>\(String(format: "%.1f", temp))</mp:temp_c>\n"
                    }
                    if let hum = point.forecastHumidity {
                        gpx += "            <mp:humidity_pct>\(String(format: "%.0f", hum))</mp:humidity_pct>\n"
                    }
                    if let pres = point.forecastPressure {
                        gpx += "            <mp:pressure_hpa>\(String(format: "%.1f", pres))</mp:pressure_hpa>\n"
                    }
                    gpx += "          </mp:weather>\n"
                }
                if point.measuredTemperature != nil || point.humidity != nil || point.pressure != nil {
                    gpx += "          <mp:sensor source=\"ruuvitag\" type=\"measured\">\n"
                    if let temp = point.measuredTemperature {
                        gpx += "            <mp:temp_c>\(String(format: "%.2f", temp))</mp:temp_c>\n"
                    }
                    if let hum = point.humidity {
                        gpx += "            <mp:humidity_pct>\(String(format: "%.2f", hum))</mp:humidity_pct>\n"
                    }
                    if let pres = point.pressure {
                        gpx += "            <mp:pressure_hpa>\(String(format: "%.2f", pres))</mp:pressure_hpa>\n"
                    }
                    gpx += "          </mp:sensor>\n"
                }
                gpx += "        </extensions>\n"
            }
            gpx += "      </trkpt>\n"
        }

        gpx += """
            </trkseg>
          </trk>
        </gpx>
        """

        return gpx
    }

    private static func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
