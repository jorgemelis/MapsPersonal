import Foundation
import CoreLocation

// MARK: - Geology Identify Service

/// Identifies geological units at a given coordinate using the IGME MAGNA 50 MapServer
enum GeologyIdentifyService {

    struct GeologyInfo {
        let unitId: String
        let description: String
        let sheetNumber: String
    }

    /// Identify the geological unit at a coordinate
    static func identify(at coordinate: CLLocationCoordinate2D) async -> GeologyInfo? {
        let lon = coordinate.longitude
        let lat = coordinate.latitude

        let extent = "\(lon - 0.01),\(lat - 0.01),\(lon + 0.01),\(lat + 0.01)"

        var components = URLComponents(string: "https://mapas.igme.es/gis/rest/services/Cartografia_Geologica/IGME_MAGNA_50/MapServer/identify")!
        components.queryItems = [
            URLQueryItem(name: "geometry", value: "\(lon),\(lat)"),
            URLQueryItem(name: "geometryType", value: "esriGeometryPoint"),
            URLQueryItem(name: "sr", value: "4326"),
            URLQueryItem(name: "layers", value: "all:11"),
            URLQueryItem(name: "tolerance", value: "3"),
            URLQueryItem(name: "mapExtent", value: extent),
            URLQueryItem(name: "imageDisplay", value: "256,256,96"),
            URLQueryItem(name: "returnGeometry", value: "false"),
            URLQueryItem(name: "f", value: "json"),
        ]

        guard let url = components.url else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let first = results.first,
                  let attrs = first["attributes"] as? [String: Any] else {
                return nil
            }

            let unitId = attrs["ID"] as? Int ?? attrs["unidad cartográfica"] as? Int ?? 0
            let description = attrs["DLO"] as? String ?? attrs["descripción litológica"] as? String ?? "Desconocido"
            let sheet = attrs["HOJA"] as? String ?? attrs["nº de hoja"] as? String ?? ""

            return GeologyInfo(
                unitId: "\(unitId)",
                description: description,
                sheetNumber: sheet
            )
        } catch {
            print("GeologyIdentify error: \(error)")
            return nil
        }
    }
}
