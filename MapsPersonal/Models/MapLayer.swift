import Foundation
import CoreLocation

// MARK: - Map Layer Definition

enum MapLayerCategory {
    case base
    case overlay
}

enum MapLayer: String, CaseIterable, Identifiable {
    case osm
    case openTopo
    case esriImagery
    case ignMTN
    case ignPNOA
    case ignFrance
    case belgiumNGI
    case igmeGeological

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .osm: return "OpenStreetMap"
        case .openTopo: return "OpenTopoMap"
        case .esriImagery: return "Satélite (ESRI)"
        case .ignMTN: return "Topográfico (IGN España)"
        case .ignPNOA: return "Ortofoto (PNOA España)"
        case .ignFrance: return "Topográfico (IGN France)"
        case .belgiumNGI: return "Topográfico (NGI Belgium)"
        case .igmeGeological: return "Geológico MAGNA 50"
        }
    }

    var category: MapLayerCategory {
        switch self {
        case .osm, .openTopo, .esriImagery, .ignMTN, .ignPNOA, .ignFrance, .belgiumNGI:
            return .base
        case .igmeGeological: return .overlay
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
        case .openTopo: return 17
        case .esriImagery: return 18
        case .ignMTN: return 20
        case .ignPNOA: return 20
        case .ignFrance: return 18
        case .belgiumNGI: return 17
        case .igmeGeological: return 16
        }
    }

    var isTransparent: Bool {
        category == .overlay
    }

    var tileURLTemplate: String? {
        switch self {
        case .osm:
            return "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
        case .openTopo:
            return "https://tile.opentopomap.org/{z}/{x}/{y}.png"
        case .esriImagery:
            return "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
        case .ignMTN:
            return "https://www.ign.es/wmts/mapa-raster?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=MTN&STYLE=default&TILEMATRIXSET=GoogleMapsCompatible&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image/jpeg"
        case .ignPNOA:
            return "https://www.ign.es/wmts/pnoa-ma?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=OI.OrthoimageCoverage&STYLE=default&TILEMATRIXSET=GoogleMapsCompatible&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image/jpeg"
        case .ignFrance:
            return "https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2&STYLE=normal&FORMAT=image/png&TILEMATRIXSET=PM&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}"
        case .belgiumNGI:
            return "https://cartoweb.wmts.ngi.be/1.0.0/topo/default/3857/{z}/{y}/{x}.png"
        case .igmeGeological:
            return "https://mapas.igme.es/gis/rest/services/Cartografia_Geologica/IGME_MAGNA_50/MapServer/export?bbox={bbox-epsg-3857}&bboxSR=3857&imageSR=3857&size=256,256&format=png32&transparent=true&layers=show:0,2&f=image"
        }
    }

    var attribution: String {
        switch self {
        case .osm: return "© OpenStreetMap contributors"
        case .openTopo: return "© OpenTopoMap (CC-BY-SA)"
        case .esriImagery: return "© Esri"
        case .ignMTN, .ignPNOA: return "© IGN España"
        case .ignFrance: return "© IGN France"
        case .belgiumNGI: return "© NGI Belgium"
        case .igmeGeological: return "© IGME"
        }
    }

    static var baseLayers: [MapLayer] {
        allCases.filter { $0.category == .base }
    }

    static var overlayLayers: [MapLayer] {
        allCases.filter { $0.category == .overlay }
    }
}
