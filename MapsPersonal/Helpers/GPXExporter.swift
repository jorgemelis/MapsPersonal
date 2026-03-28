import Foundation

// MARK: - GPX Exporter

enum GPXExporter {
    static func export(track: GPXTrack) -> String {
        let iso = ISO8601DateFormatter()
        let hasHR = track.points.contains { $0.heartRate != nil }

        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="MapsPersonal"
             xmlns="http://www.topografix.com/GPX/1/1"
             xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        """

        if hasHR {
            gpx += "     xmlns:gpxtpx=\"http://www.garmin.com/xmlschemas/TrackPointExtension/v1\"\n"
            gpx += "     xsi:schemaLocation=\"http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd\">\n"
        } else {
            gpx += "     xsi:schemaLocation=\"http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd\">\n"
        }

        gpx += """
          <metadata>
            <name>\(escapeXML(track.name))</name>
            <time>\(iso.string(from: track.startDate))</time>
          </metadata>
          <trk>
            <name>\(escapeXML(track.name))</name>
            <trkseg>

        """

        for point in track.points {
            gpx += "      <trkpt lat=\"\(point.latitude)\" lon=\"\(point.longitude)\">\n"
            if let ele = point.elevation {
                gpx += "        <ele>\(String(format: "%.1f", ele))</ele>\n"
            }
            gpx += "        <time>\(iso.string(from: point.timestamp))</time>\n"
            if let hr = point.heartRate {
                gpx += "        <extensions>\n"
                gpx += "          <gpxtpx:TrackPointExtension>\n"
                gpx += "            <gpxtpx:hr>\(hr)</gpxtpx:hr>\n"
                gpx += "          </gpxtpx:TrackPointExtension>\n"
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
