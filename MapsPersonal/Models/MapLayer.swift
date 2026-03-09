import Foundation
import CoreLocation

// MARK: - Map Layer Definition

enum MapLayerCategory {
    case base
    case overlay
}

enum MapLayer: String, CaseIterable, Identifiable {
    case osm
    case esriImagery
    case ignMTN
    case ignPNOA
    case igmeGeological
    case igmeGeologicalOffline
    case ignMTNOffline

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .osm: return "OpenStreetMap"
        case .esriImagery: return "Satélite (ESRI)"
        case .ignMTN: return "Topográfico (IGN)"
        case .ignPNOA: return "Ortofoto (PNOA)"
        case .igmeGeological: return "Geológico MAGNA 50 (online)"
        case .igmeGeologicalOffline: return "Geológico MAGNA 50 (offline)"
        case .ignMTNOffline: return "Topográfico IGN (offline)"
        }
    }

    var category: MapLayerCategory {
        switch self {
        case .osm, .esriImagery, .ignMTN, .ignPNOA: return .base
        case .ignMTNOffline: return .base
        case .igmeGeological, .igmeGeologicalOffline: return .overlay
        }
    }

    var tileSize: Int {
        switch self {
        case .igmeGeological: return 512
        default: return 256
        }
    }

    var maxZoom: Int {
        switch self {
        case .osm: return 19
        case .esriImagery: return 18
        case .ignMTN: return 20
        case .ignPNOA: return 20
        case .igmeGeological: return 16
        case .igmeGeologicalOffline: return 15
        case .ignMTNOffline: return 16
        }
    }

    var isTransparent: Bool {
        category == .overlay
    }

    /// Returns nil for layers that need a dynamic URL (e.g. local tile server)
    var tileURLTemplate: String? {
        switch self {
        case .osm:
            return "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
        case .esriImagery:
            return "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
        case .ignMTN:
            return "https://www.ign.es/wmts/mapa-raster?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=MTN&STYLE=default&TILEMATRIXSET=GoogleMapsCompatible&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image/jpeg"
        case .ignPNOA:
            return "https://www.ign.es/wmts/pnoa-ma?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=OI.OrthoimageCoverage&STYLE=default&TILEMATRIXSET=GoogleMapsCompatible&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image/jpeg"
        case .igmeGeological:
            return "https://mapas.igme.es/gis/rest/services/Cartografia_Geologica/IGME_MAGNA_50/MapServer/export?bbox={bbox-epsg-3857}&bboxSR=3857&imageSR=3857&size=256,256&format=png32&transparent=true&layers=show:0,2&f=image"
        case .igmeGeologicalOffline:
            return nil // Set dynamically from LocalTileServer
        case .ignMTNOffline:
            return nil // Set dynamically from LocalTileServer
        }
    }

    var attribution: String {
        switch self {
        case .osm: return "© OpenStreetMap contributors"
        case .esriImagery: return "© Esri"
        case .ignMTN, .ignPNOA: return "© IGN España"
        case .igmeGeological, .igmeGeologicalOffline: return "© IGME"
        case .ignMTNOffline: return "© IGN España"
        }
    }

    static var baseLayers: [MapLayer] {
        allCases.filter { $0.category == .base }
    }

    static var overlayLayers: [MapLayer] {
        allCases.filter { $0.category == .overlay }
    }
}
