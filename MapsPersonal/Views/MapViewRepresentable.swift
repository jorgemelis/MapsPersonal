import SwiftUI
import MapLibre

// MARK: - MapLibre Map View (UIViewRepresentable)

struct MapViewRepresentable: UIViewRepresentable {
    let mapState: MapState
    let trackRecorder: TrackRecorder
    var onCameraChange: ((CLLocationCoordinate2D, Double) -> Void)?

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero)

        // Load blank style from bundle
        if let styleURL = Bundle.main.url(forResource: "blank-style", withExtension: "json") {
            mapView.styleURL = styleURL
        }

        mapView.delegate = context.coordinator
        mapView.showsUserLocation = mapState.showsUserLocation
        mapView.compassViewPosition = .topRight
        mapView.logoView.isHidden = true

        // Restore saved camera position
        mapView.setCenter(mapState.centerCoordinate, zoomLevel: mapState.zoomLevel, animated: false)

        // Gesture: long press to show coordinates
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        mapView.addGestureRecognizer(longPress)

        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        mapView.showsUserLocation = mapState.showsUserLocation

        if mapState.isFollowingUser, let loc = mapView.userLocation?.location?.coordinate {
            mapView.setCenter(loc, animated: true)
        }

        // Sync layers when style is loaded
        if let style = mapView.style {
            context.coordinator.syncLayers(style: style, state: mapState)
            context.coordinator.syncTrackOverlay(mapView: mapView, recorder: trackRecorder)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MLNMapViewDelegate {
        let parent: MapViewRepresentable
        private var currentBaseLayer: MapLayer?
        private var currentOverlays: Set<MapLayer> = []
        private var currentDynamicLayers: Set<String> = []
        private var trackAnnotation: MLNPolyline?

        init(parent: MapViewRepresentable) {
            self.parent = parent
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            syncLayers(style: style, state: parent.mapState)
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            parent.mapState.centerCoordinate = mapView.centerCoordinate
            parent.mapState.zoomLevel = mapView.zoomLevel
            parent.onCameraChange?(mapView.centerCoordinate, mapView.zoomLevel)
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            guard let mapView = gesture.view as? MLNMapView else { return }
            let point = gesture.location(in: mapView)
            let coord = mapView.convert(point, toCoordinateFrom: mapView)

            // Add/replace pin annotation
            if let existing = mapView.annotations {
                let pins = existing.compactMap { $0 as? MLNPointAnnotation }
                mapView.removeAnnotations(pins)
            }

            let pin = MLNPointAnnotation()
            pin.coordinate = coord
            pin.title = String(format: "%.6f, %.6f", coord.latitude, coord.longitude)
            mapView.addAnnotation(pin)
            mapView.selectAnnotation(pin, animated: true, completionHandler: nil)
        }

        func mapView(_ mapView: MLNMapView, annotationCanShowCallout annotation: MLNAnnotation) -> Bool {
            true
        }

        // MARK: - Layer Sync

        func syncLayers(style: MLNStyle, state: MapState) {
            let desiredBase = state.activeBaseLayer
            let desiredOverlays = state.activeOverlays

            // Update base layer if changed
            if currentBaseLayer != desiredBase {
                // Remove old base
                if let old = currentBaseLayer {
                    removeLayer(old, from: style)
                }
                // Add new base
                addLayer(desiredBase, to: style, opacity: 1.0)
                currentBaseLayer = desiredBase
            }

            // Remove overlays that are no longer active
            for overlay in currentOverlays {
                if !desiredOverlays.contains(overlay) {
                    removeLayer(overlay, from: style)
                }
            }

            // Add new overlays
            for overlay in desiredOverlays {
                if !currentOverlays.contains(overlay) {
                    let opacity = state.opacityFor(overlay)
                    addLayer(overlay, to: style, opacity: opacity)
                }
            }

            // Update opacity for existing overlays
            for overlay in desiredOverlays {
                let layerId = "\(overlay.rawValue)-layer"
                if let styleLayer = style.layer(withIdentifier: layerId) as? MLNRasterStyleLayer {
                    let opacity = state.opacityFor(overlay)
                    styleLayer.rasterOpacity = NSExpression(forConstantValue: NSNumber(value: opacity))
                }
            }

            currentOverlays = desiredOverlays

            // Sync dynamic offline layers
            syncDynamicLayers(style: style, state: state)
        }

        private func syncDynamicLayers(style: MLNStyle, state: MapState) {
            let desired = Set(state.activeDynamicOverlays)

            // Remove layers no longer active
            for id in currentDynamicLayers where !desired.contains(id) {
                if let layer = style.layer(withIdentifier: "dyn-\(id)-layer") {
                    style.removeLayer(layer)
                }
                if let source = style.source(withIdentifier: "dyn-\(id)") {
                    style.removeSource(source)
                }
            }

            // Add new dynamic layers
            for id in desired where !currentDynamicLayers.contains(id) {
                guard let url = state.dynamicOfflineLayers[id] else { continue }
                let source = MLNRasterTileSource(
                    identifier: "dyn-\(id)",
                    tileURLTemplates: [url],
                    options: [
                        .tileSize: NSNumber(value: 256),
                        .maximumZoomLevel: NSNumber(value: 16)
                    ]
                )
                let layer = MLNRasterStyleLayer(identifier: "dyn-\(id)-layer", source: source)
                let opacity = state.dynamicOverlayOpacity[id] ?? 0.7
                layer.rasterOpacity = NSExpression(forConstantValue: NSNumber(value: opacity))
                style.addSource(source)
                style.addLayer(layer)
            }

            currentDynamicLayers = desired
        }

        private func addLayer(_ layer: MapLayer, to style: MLNStyle, opacity: Double) {
            let urlOverride: String? = parent.mapState.offlineTileURLs[layer]
            let source = TileSourceFactory.makeSource(for: layer, urlOverride: urlOverride)
            let styleLayer = TileSourceFactory.makeStyleLayer(for: layer, source: source, opacity: opacity)
            style.addSource(source)
            style.addLayer(styleLayer)
        }

        private func removeLayer(_ layer: MapLayer, from style: MLNStyle) {
            let layerId = "\(layer.rawValue)-layer"
            if let existingLayer = style.layer(withIdentifier: layerId) {
                style.removeLayer(existingLayer)
            }
            if let existingSource = style.source(withIdentifier: layer.rawValue) {
                style.removeSource(existingSource)
            }
        }

        // MARK: - Track Overlay

        func syncTrackOverlay(mapView: MLNMapView, recorder: TrackRecorder) {
            // Remove old track line
            if let existing = trackAnnotation {
                mapView.removeAnnotation(existing)
                trackAnnotation = nil
            }

            // Draw current track
            guard let track = recorder.currentTrack, track.points.count > 1 else { return }
            var coords = track.coordinates
            let polyline = MLNPolyline(coordinates: &coords, count: UInt(coords.count))
            mapView.addAnnotation(polyline)
            trackAnnotation = polyline
        }

        func mapView(_ mapView: MLNMapView, strokeColorForShapeAnnotation annotation: MLNShape) -> UIColor {
            .systemRed
        }

        func mapView(_ mapView: MLNMapView, lineWidthForPolylineAnnotation annotation: MLNPolyline) -> CGFloat {
            3.0
        }
    }
}
