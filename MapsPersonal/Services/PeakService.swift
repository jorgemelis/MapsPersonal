import Foundation
import CoreLocation

// MARK: - Peak

struct Peak: Identifiable, Codable {
    let id: Int64          // OSM node ID
    let name: String
    let elevation: Int?    // meters
    let lat: Double
    let lon: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var label: String {
        if let ele = elevation {
            return "\(name) (\(ele) m)"
        }
        return name
    }
}

// MARK: - Peak Service

@Observable
class PeakService {
    var peaks: [Peak] = []
    var isLoading = false

    /// Bounding box of the last successful fetch (to avoid re-fetching)
    private var lastBBox: (south: Double, west: Double, north: Double, east: Double)?
    private var cache: [Peak] = []

    /// Fetch peaks from OSM Overpass API for the visible map area
    func fetchPeaks(south: Double, west: Double, north: Double, east: Double) async {
        // Skip if we already have data covering this area
        if let last = lastBBox,
           south >= last.south, west >= last.west,
           north <= last.north, east <= last.east {
            return
        }

        // Expand bbox by 20% to avoid re-fetching on small pans
        let latPad = (north - south) * 0.2
        let lonPad = (east - west) * 0.2
        let s = south - latPad
        let n = north + latPad
        let w = west - lonPad
        let e = east + lonPad

        let query = """
        [out:json][timeout:15];
        node["natural"="peak"]["name"](
          \(s),\(w),\(n),\(e)
        );
        out body;
        """

        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://overpass-api.de/api/interpreter?data=\(encoded)") else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(OverpassResponse.self, from: data)

            let newPeaks = response.elements.compactMap { elem -> Peak? in
                guard let name = elem.tags?["name"] else { return nil }
                let ele = elem.tags?["ele"].flatMap { Int(Double($0) ?? 0) }
                return Peak(id: elem.id, name: name, elevation: ele, lat: elem.lat, lon: elem.lon)
            }

            await MainActor.run {
                self.peaks = newPeaks
                self.cache = newPeaks
                self.lastBBox = (s, w, n, e)
            }
        } catch {
            // On error, keep showing cached data
            print("Peak fetch error: \(error.localizedDescription)")
        }
    }

    /// Clear cache (e.g., when zooming out a lot)
    func clearCache() {
        peaks = []
        cache = []
        lastBBox = nil
    }
}

// MARK: - Overpass API response

private struct OverpassResponse: Decodable {
    let elements: [OverpassElement]
}

private struct OverpassElement: Decodable {
    let id: Int64
    let lat: Double
    let lon: Double
    let tags: [String: String]?
}
