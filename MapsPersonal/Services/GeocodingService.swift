import Foundation
import CoreLocation

// MARK: - Geocoding Service

struct GeocodingResult: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
}

enum GeocodingService {
    /// Search for places using Nominatim (OpenStreetMap)
    static func search(_ query: String) async -> [GeocodingResult] {
        guard !query.isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://nominatim.openstreetmap.org/search?q=\(encoded)&format=json&limit=5&addressdetails=1")
        else { return [] }

        var request = URLRequest(url: url)
        request.setValue("MapsPersonal/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let items = try JSONDecoder().decode([NominatimResult].self, from: data)
            return items.compactMap { item in
                guard let lat = Double(item.lat), let lon = Double(item.lon) else { return nil }
                return GeocodingResult(
                    name: item.display_name,
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
                )
            }
        } catch {
            return []
        }
    }
}

private struct NominatimResult: Decodable {
    let lat: String
    let lon: String
    let display_name: String
}
