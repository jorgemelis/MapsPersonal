import MapLibre

// MARK: - Tile Source Factory

enum TileSourceFactory {

    static func makeSource(for layer: MapLayer, urlOverride: String? = nil) -> MLNRasterTileSource {
        let url = urlOverride ?? layer.tileURLTemplate ?? ""
        return MLNRasterTileSource(
            identifier: layer.rawValue,
            tileURLTemplates: [url],
            options: [
                .tileSize: NSNumber(value: layer.tileSize),
                .maximumZoomLevel: NSNumber(value: layer.maxZoom)
            ]
        )
    }

    static func makeStyleLayer(for layer: MapLayer, source: MLNRasterTileSource, opacity: Double = 1.0) -> MLNRasterStyleLayer {
        let styleLayer = MLNRasterStyleLayer(identifier: "\(layer.rawValue)-layer", source: source)
        if opacity < 1.0 {
            styleLayer.rasterOpacity = NSExpression(forConstantValue: NSNumber(value: opacity))
        }
        return styleLayer
    }
}
