import SwiftUI
import MapLibre

// MARK: - MapLibre Map View (UIViewRepresentable)

struct MapViewRepresentable: UIViewRepresentable {
    let mapState: MapState
    let trackRecorder: TrackRecorder
    let tractiveService: TractiveService?
    var onCameraChange: ((CLLocationCoordinate2D, Double, Double, Double) -> Void)?

    // Explicit values so SwiftUI detects changes and calls updateUIView
    var terrainVersion: Int
    var petPositionTimestamp: Date?  // triggers updateUIView when pet moves

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero)

        // Load blank style from bundle
        if let styleURL = Bundle.main.url(forResource: "blank-style", withExtension: "json") {
            mapView.styleURL = styleURL
        }

        mapView.delegate = context.coordinator
        mapView.showsUserLocation = mapState.showsUserLocation
        mapView.compassView.isHidden = true
        mapView.logoView.isHidden = true
        mapView.allowsTilting = true

        // Restore saved camera position including bearing and pitch
        mapView.setCenter(mapState.centerCoordinate, zoomLevel: mapState.zoomLevel, animated: false)
        mapView.direction = mapState.bearing
        mapView.camera.pitch = mapState.pitch

        // Gesture: long press to show coordinates
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        mapView.addGestureRecognizer(longPress)

        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        mapView.showsUserLocation = mapState.showsUserLocation

        if mapState.isFollowingUser, let loc = mapView.userLocation?.location?.coordinate {
            mapView.setCenter(loc, zoomLevel: max(mapView.zoomLevel, 14), animated: true)
        }

        // Reset north: bearing = 0, pitch = 0
        if mapState.resetNorthRequest {
            mapView.setDirection(0, animated: true)
            mapView.setCamera(
                MLNMapCamera(
                    lookingAtCenter: mapView.centerCoordinate,
                    altitude: mapView.camera.altitude,
                    pitch: 0,
                    heading: 0
                ),
                animated: true
            )
            // Defer state change to avoid "modifying state during view update"
            Task { @MainActor in
                self.mapState.resetNorthRequest = false
            }
        }

        // Sync layers when style is loaded
        if let style = mapView.style {
            context.coordinator.syncLayers(style: style, state: mapState)
            context.coordinator.syncTrackOverlay(mapView: mapView, recorder: trackRecorder)
        }

        // Sync pet annotations (independent of style)
        context.coordinator.syncPetAnnotation(mapView: mapView, tractive: tractiveService)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MLNMapViewDelegate {
        static let mapTilerKey: String = {
            guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
                  let data = try? Data(contentsOf: url),
                  let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let key = dict["MapTilerAPIKey"] as? String else {
                return ""
            }
            return key
        }()

        let parent: MapViewRepresentable
        private var currentBaseLayer: MapLayer?
        private var currentOverlays: Set<MapLayer> = []
        private var currentDynamicLayers: Set<String> = []
        private var trackAnnotation: MLNPolyline?
        private var petAnnotations: [String: MLNPointAnnotation] = [:]
        private var petTrailAnnotations: [String: MLNPolyline] = [:]
        private var hillshadeActive = false
        private var contoursActive = false

        init(parent: MapViewRepresentable) {
            self.parent = parent
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            syncLayers(style: style, state: parent.mapState)
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            let center = mapView.centerCoordinate
            let zoom = mapView.zoomLevel
            let dir = mapView.direction
            let pitch = mapView.camera.pitch
            Task { @MainActor in
                self.parent.mapState.centerCoordinate = center
                self.parent.mapState.zoomLevel = zoom
                self.parent.mapState.bearing = dir
                self.parent.mapState.pitch = pitch
            }
            parent.onCameraChange?(center, zoom, dir, pitch)
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            guard let mapView = gesture.view as? MLNMapView else { return }
            let point = gesture.location(in: mapView)
            let coord = mapView.convert(point, toCoordinateFrom: mapView)

            // Add/replace pin annotation (but keep pet annotations)
            let petPins = Set(petAnnotations.values.map { ObjectIdentifier($0) })
            if let existing = mapView.annotations {
                let pins = existing.compactMap { $0 as? MLNPointAnnotation }.filter { !petPins.contains(ObjectIdentifier($0)) }
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

            // Sync terrain layers
            syncHillshade(style: style, state: state)
            syncContours(style: style, state: state)
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
            guard let source = TileSourceFactory.makeSource(for: layer, urlOverride: urlOverride) else {
                print("⚠️ Skipping layer \(layer.rawValue): no URL available")
                return
            }
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

        // MARK: - Hillshade

        func syncHillshade(style: MLNStyle, state: MapState) {
            if state.showHillshade && !hillshadeActive {
                // Add DEM source (AWS Terrain Tiles, free, Terrarium encoding)
                let demSource = MLNRasterDEMSource(
                    identifier: "terrain-dem",
                    tileURLTemplates: ["https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"],
                    options: [
                        .tileSize: NSNumber(value: 256),
                        .maximumZoomLevel: NSNumber(value: 15)
                    ]
                )
                style.addSource(demSource)

                let layer = MLNHillshadeStyleLayer(identifier: "hillshade-layer", source: demSource)
                layer.hillshadeExaggeration = NSExpression(forConstantValue: NSNumber(value: state.hillshadeOpacity))
                layer.hillshadeIlluminationDirection = NSExpression(forConstantValue: NSNumber(value: 335))
                layer.hillshadeShadowColor = NSExpression(forConstantValue: UIColor.black.withAlphaComponent(0.15))
                layer.hillshadeHighlightColor = NSExpression(forConstantValue: UIColor.white.withAlphaComponent(0.1))
                layer.hillshadeAccentColor = NSExpression(forConstantValue: UIColor.black.withAlphaComponent(0.05))

                // Insert just above the base layer
                if let baseLayers = style.layers.first(where: { $0.identifier.hasSuffix("-layer") }) {
                    style.insertLayer(layer, above: baseLayers)
                } else {
                    style.addLayer(layer)
                }
                hillshadeActive = true

            } else if !state.showHillshade && hillshadeActive {
                if let layer = style.layer(withIdentifier: "hillshade-layer") {
                    style.removeLayer(layer)
                }
                if let source = style.source(withIdentifier: "terrain-dem") {
                    style.removeSource(source)
                }
                hillshadeActive = false
            }

            // Update opacity
            if hillshadeActive, let layer = style.layer(withIdentifier: "hillshade-layer") as? MLNHillshadeStyleLayer {
                layer.hillshadeExaggeration = NSExpression(forConstantValue: NSNumber(value: state.hillshadeOpacity))
            }
        }

        // MARK: - Contour Lines

        func syncContours(style: MLNStyle, state: MapState) {
            let key = Self.mapTilerKey
            if key.isEmpty { print("⚠️ MapTiler API key is empty - Secrets.plist not loaded"); return }

            if state.showContours && !contoursActive {
                // Guard against duplicate source
                if style.source(withIdentifier: "contours-source") != nil {
                    print("📍 Contour source already exists, skipping add")
                    contoursActive = true
                    return
                }
                let url = "https://api.maptiler.com/tiles/contours-v2/{z}/{x}/{y}.pbf?key=\(key)"
                print("📍 Adding contour source: \(url)")
                let source = MLNVectorTileSource(
                    identifier: "contours-source",
                    tileURLTemplates: [url],
                    options: [
                        .minimumZoomLevel: NSNumber(value: 9),
                        .maximumZoomLevel: NSNumber(value: 14)
                    ]
                )
                style.addSource(source)
                print("📍 Contour source added, layers: \(style.layers.map { $0.identifier })")

                // Minor contour lines
                let minorLines = MLNLineStyleLayer(identifier: "contour-minor", source: source)
                minorLines.sourceLayerIdentifier = "contour"
                minorLines.predicate = NSPredicate(format: "nth_line < 5")
                minorLines.lineColor = NSExpression(forConstantValue: UIColor(red: 1.0, green: 0.85, blue: 0.5, alpha: 0.6))
                minorLines.lineWidth = NSExpression(forConstantValue: NSNumber(value: 0.8))
                minorLines.minimumZoomLevel = 12
                style.addLayer(minorLines)

                // Index (major) contour lines - nth_line >= 5
                let majorLines = MLNLineStyleLayer(identifier: "contour-major", source: source)
                majorLines.sourceLayerIdentifier = "contour"
                majorLines.predicate = NSPredicate(format: "nth_line >= 5")
                majorLines.lineColor = NSExpression(forConstantValue: UIColor(red: 1.0, green: 0.75, blue: 0.3, alpha: 0.9))
                majorLines.lineWidth = NSExpression(forConstantValue: NSNumber(value: 1.5))
                majorLines.minimumZoomLevel = 9
                style.addLayer(majorLines)

                // Elevation labels on major contours
                let labels = MLNSymbolStyleLayer(identifier: "contour-labels", source: source)
                labels.sourceLayerIdentifier = "contour"
                labels.predicate = NSPredicate(format: "nth_line >= 5")
                labels.text = NSExpression(forKeyPath: "height")
                labels.symbolPlacement = NSExpression(forConstantValue: "line")
                labels.textFontSize = NSExpression(forConstantValue: NSNumber(value: 11))
                labels.textColor = NSExpression(forConstantValue: UIColor(red: 1.0, green: 0.85, blue: 0.4, alpha: 1.0))
                labels.textHaloColor = NSExpression(forConstantValue: UIColor.black.withAlphaComponent(0.7))
                labels.textHaloWidth = NSExpression(forConstantValue: NSNumber(value: 1.5))
                labels.minimumZoomLevel = 12
                style.addLayer(labels)

                contoursActive = true

            } else if !state.showContours && contoursActive {
                for id in ["contour-labels", "contour-major", "contour-minor"] {
                    if let layer = style.layer(withIdentifier: id) {
                        style.removeLayer(layer)
                    }
                }
                if let source = style.source(withIdentifier: "contours-source") {
                    style.removeSource(source)
                }
                contoursActive = false
            }

            // Update opacity
            if contoursActive {
                let alpha = state.contourOpacity
                if let minor = style.layer(withIdentifier: "contour-minor") as? MLNLineStyleLayer {
                    minor.lineColor = NSExpression(forConstantValue: UIColor(red: 1.0, green: 0.85, blue: 0.5, alpha: alpha * 0.7))
                    minor.lineWidth = NSExpression(forConstantValue: NSNumber(value: 0.4 + alpha * 0.8))
                }
                if let major = style.layer(withIdentifier: "contour-major") as? MLNLineStyleLayer {
                    major.lineColor = NSExpression(forConstantValue: UIColor(red: 1.0, green: 0.75, blue: 0.3, alpha: alpha))
                    major.lineWidth = NSExpression(forConstantValue: NSNumber(value: 0.8 + alpha * 1.5))
                }
                if let labels = style.layer(withIdentifier: "contour-labels") as? MLNSymbolStyleLayer {
                    labels.textColor = NSExpression(forConstantValue: UIColor(red: 1.0, green: 0.85, blue: 0.4, alpha: alpha))
                }
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
            // Pet trails in orange, user track in red
            if let polyline = annotation as? MLNPolyline,
               petTrailAnnotations.values.contains(where: { $0 === polyline }) {
                return .systemOrange
            }
            return .systemRed
        }

        func mapView(_ mapView: MLNMapView, lineWidthForPolylineAnnotation annotation: MLNPolyline) -> CGFloat {
            // Pet trails slightly thinner
            if petTrailAnnotations.values.contains(where: { $0 === annotation }) {
                return 2.5
            }
            return 3.0
        }

        // MARK: - Pet Annotations (Tractive)

        func syncPetAnnotation(mapView: MLNMapView, tractive: TractiveService?) {
            guard let tractive else {
                // Remove all pet annotations and trails
                for (_, pin) in petAnnotations { mapView.removeAnnotation(pin) }
                for (_, trail) in petTrailAnnotations { mapView.removeAnnotation(trail) }
                petAnnotations.removeAll()
                petTrailAnnotations.removeAll()
                return
            }

            let visiblePets = tractive.visiblePets
            let visibleIds = Set(visiblePets.map { $0.id })

            // Remove annotations for pets no longer visible
            for (petId, pin) in petAnnotations where !visibleIds.contains(petId) {
                mapView.removeAnnotation(pin)
                petAnnotations.removeValue(forKey: petId)
            }
            for (petId, trail) in petTrailAnnotations where !visibleIds.contains(petId) {
                mapView.removeAnnotation(trail)
                petTrailAnnotations.removeValue(forKey: petId)
            }

            // Add or update annotations for visible pets
            for pet in visiblePets {
                guard let pos = pet.position else { continue }

                if let existing = petAnnotations[pet.id] {
                    existing.coordinate = pos.coordinate
                    existing.title = petTitle(pet)
                    existing.subtitle = petSubtitle(pos)
                } else {
                    let pin = MLNPointAnnotation()
                    pin.coordinate = pos.coordinate
                    pin.title = petTitle(pet)
                    pin.subtitle = petSubtitle(pos)
                    print("🐾 Adding pin for \(pet.name) at \(pos.coordinate.latitude), \(pos.coordinate.longitude)")
                    mapView.addAnnotation(pin)
                    petAnnotations[pet.id] = pin
                }

                // Draw pet trail (during hike mode)
                var trail = tractive.trail(for: pet.id)
                if trail.count > 1 {
                    // Remove old trail polyline
                    if let old = petTrailAnnotations[pet.id] {
                        mapView.removeAnnotation(old)
                    }
                    let polyline = MLNPolyline(coordinates: &trail, count: UInt(trail.count))
                    mapView.addAnnotation(polyline)
                    petTrailAnnotations[pet.id] = polyline
                }
            }
        }

        private func petTitle(_ pet: TractivePet) -> String {
            var title = "\(pet.emoji) \(pet.name)"
            if let battery = pet.batteryLevel, battery > 0 {
                title += " \(battery)%"
                if pet.isCharging { title += "⚡" }
            }
            return title
        }

        private func petSubtitle(_ pos: TractivePosition) -> String {
            let ago = Int(-pos.timestamp.timeIntervalSinceNow)
            if ago < 60 { return "ahora" }
            if ago < 3600 { return "hace \(ago / 60) min" }
            return "hace \(ago / 3600)h"
        }

        // Use default pin for all annotations (including pets)
        // Pet pins show title "🐕 Odín 96%" via callout
    }
}
