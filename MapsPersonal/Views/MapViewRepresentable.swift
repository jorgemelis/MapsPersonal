import SwiftUI
import MapLibre

// MARK: - MapLibre Map View (UIViewRepresentable)

struct MapViewRepresentable: UIViewRepresentable {
    let mapState: MapState
    let trackRecorder: TrackRecorder
    let tractiveService: TractiveService?
    let peakService: PeakService?
    var onCameraChange: ((CLLocationCoordinate2D, Double, Double, Double) -> Void)?

    // Explicit values so SwiftUI detects changes and calls updateUIView
    var terrainVersion: Int
    var trackVersion: Int  // triggers updateUIView when new GPS points are added
    var petPositionTimestamp: Date?  // triggers updateUIView when pet moves

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero)

        // Load blank style from bundle
        if let styleURL = Bundle.main.url(forResource: "blank-style", withExtension: "json") {
            mapView.styleURL = styleURL
        }

        context.coordinator.mapViewRef = mapView
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

        // Fly to searched location
        if let target = mapState.flyToCoordinate {
            mapView.setCenter(target, zoomLevel: 14, animated: true)
            Task { @MainActor in
                self.mapState.flyToCoordinate = nil
                self.mapState.isFollowingUser = false
            }
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
            context.coordinator.syncTrackOverlay(mapView: mapView, style: style, recorder: trackRecorder)
            context.coordinator.syncPeaks(mapView: mapView, style: style, state: mapState, peakService: peakService)
        } else {
            // Track overlay via annotations as fallback before style loads
            context.coordinator.syncTrackOverlayAnnotation(mapView: mapView, recorder: trackRecorder)
        }

        // Sync pet annotations (independent of style)
        context.coordinator.syncPetAnnotation(mapView: mapView, tractive: tractiveService)
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
        private var petAnnotations: [String: MLNPointAnnotation] = [:]
        private var petTrailAnnotations: [String: MLNPolyline] = [:]
        private var peaksActive = false
        weak var mapViewRef: MLNMapView?

        init(parent: MapViewRepresentable) {
            self.parent = parent
            super.init()

            // Listen for track point additions to update polyline directly
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleTrackPointAdded(_:)),
                name: .trackPointAdded,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func handleTrackPointAdded(_ notification: Notification) {
            guard let mapView = mapViewRef,
                  let style = mapView.style,
                  let recorder = notification.object as? TrackRecorder else { return }
            syncTrackOverlay(mapView: mapView, style: style, recorder: recorder)
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            self.mapViewRef = mapView
            syncLayers(style: style, state: parent.mapState)
            syncTrackOverlay(mapView: mapView, style: style, recorder: parent.trackRecorder)
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

            // If geological overlay is active, identify the unit
            if parent.mapState.activeOverlays.contains(.igmeGeological) ||
               parent.mapState.activeDynamicOverlays.contains(where: { id in
                   id.lowercased().contains("geolog") || id.lowercased().contains("magna")
               }) {
                Task {
                    if let info = await GeologyIdentifyService.identify(at: coord) {
                        await MainActor.run {
                            pin.subtitle = "[\(info.unitId)] \(info.description)"
                            // Re-select to show updated callout
                            mapView.deselectAnnotation(pin, animated: false)
                            mapView.selectAnnotation(pin, animated: true, completionHandler: nil)
                        }
                    }
                }
            }
        }

        func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            // Only customize pet annotations (identified by emoji in title)
            guard let point = annotation as? MLNPointAnnotation,
                  let title = point.title,
                  (title.contains("🐕") || title.contains("🐱")) else {
                return nil // default pin for other annotations
            }

            let reuseId = "pet"
            var view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseId)
            if view == nil {
                view = MLNAnnotationView(reuseIdentifier: reuseId)
                view?.frame = CGRect(x: 0, y: 0, width: 36, height: 36)

                let circle = UIView(frame: view!.bounds)
                circle.backgroundColor = .systemOrange
                circle.layer.cornerRadius = 18
                circle.layer.borderWidth = 2
                circle.layer.borderColor = UIColor.white.cgColor
                circle.layer.shadowColor = UIColor.black.cgColor
                circle.layer.shadowOpacity = 0.3
                circle.layer.shadowOffset = CGSize(width: 0, height: 2)
                circle.layer.shadowRadius = 3
                circle.tag = 100
                view?.addSubview(circle)

                let label = UILabel(frame: view!.bounds)
                label.textAlignment = .center
                label.font = .systemFont(ofSize: 20)
                label.tag = 101
                view?.addSubview(label)
            }

            // Update emoji
            let emoji = title.contains("🐱") ? "🐱" : "🐕"
            if let label = view?.viewWithTag(101) as? UILabel {
                label.text = emoji
            }

            return view
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

            // Clean up legacy terrain layers if still present
            cleanupLegacyTerrainLayers(style: style)
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

            // Update opacity for existing dynamic layers
            for id in desired {
                let layerId = "dyn-\(id)-layer"
                if let styleLayer = style.layer(withIdentifier: layerId) as? MLNRasterStyleLayer {
                    let opacity = state.dynamicOverlayOpacity[id] ?? 0.7
                    styleLayer.rasterOpacity = NSExpression(forConstantValue: NSNumber(value: opacity))
                }
            }

            currentDynamicLayers = desired
        }

        private func addLayer(_ layer: MapLayer, to style: MLNStyle, opacity: Double) {
            guard let source = TileSourceFactory.makeSource(for: layer) else {
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

        // MARK: - Legacy Terrain Cleanup

        /// Remove hillshade/contour layers from previous sessions (one-time cleanup)
        private func cleanupLegacyTerrainLayers(style: MLNStyle) {
            // Hillshade
            if let layer = style.layer(withIdentifier: "hillshade-layer") {
                style.removeLayer(layer)
            }
            if let source = style.source(withIdentifier: "terrain-dem") {
                style.removeSource(source)
            }
            // Contours
            for id in ["contour-labels", "contour-major", "contour-minor"] {
                if let layer = style.layer(withIdentifier: id) {
                    style.removeLayer(layer)
                }
            }
            if let source = style.source(withIdentifier: "contours-source") {
                style.removeSource(source)
            }
        }

        // MARK: - Peaks

        func syncPeaks(mapView: MLNMapView, style: MLNStyle, state: MapState, peakService: PeakService?) {
            if state.showPeaks {
                guard let service = peakService else { return }

                // Fetch peaks for visible area
                let bounds = mapView.visibleCoordinateBounds
                Task {
                    await service.fetchPeaks(
                        south: bounds.sw.latitude,
                        west: bounds.sw.longitude,
                        north: bounds.ne.latitude,
                        east: bounds.ne.longitude
                    )
                    await MainActor.run {
                        self.updatePeakLayer(style: style, peaks: service.peaks)
                    }
                }
                peaksActive = true

            } else if peaksActive {
                // Remove peak layers
                for id in ["peaks-labels", "peaks-circles"] {
                    if let layer = style.layer(withIdentifier: id) {
                        style.removeLayer(layer)
                    }
                }
                if let source = style.source(withIdentifier: "peaks-source") {
                    style.removeSource(source)
                }
                peaksActive = false
            }
        }

        private func updatePeakLayer(style: MLNStyle, peaks: [Peak]) {
            // Remove existing source/layers to update
            for id in ["peaks-labels", "peaks-circles"] {
                if let layer = style.layer(withIdentifier: id) {
                    style.removeLayer(layer)
                }
            }
            if let source = style.source(withIdentifier: "peaks-source") {
                style.removeSource(source)
            }

            guard !peaks.isEmpty else { return }

            // Create GeoJSON features
            let features = peaks.map { peak -> MLNPointFeature in
                let feature = MLNPointFeature()
                feature.coordinate = peak.coordinate
                feature.attributes = [
                    "name": peak.name,
                    "elevation": peak.elevation ?? 0,
                    "label": peak.label
                ]
                return feature
            }

            let source = MLNShapeSource(identifier: "peaks-source", features: features, options: nil)
            style.addSource(source)

            // Triangle/dot marker for peaks
            let circles = MLNCircleStyleLayer(identifier: "peaks-circles", source: source)
            circles.circleRadius = NSExpression(forConstantValue: NSNumber(value: 4))
            circles.circleColor = NSExpression(forConstantValue: UIColor.systemBrown)
            circles.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            circles.circleStrokeWidth = NSExpression(forConstantValue: NSNumber(value: 1.5))
            circles.minimumZoomLevel = 10
            style.addLayer(circles)

            // Peak name + elevation labels
            let labels = MLNSymbolStyleLayer(identifier: "peaks-labels", source: source)
            labels.text = NSExpression(forKeyPath: "label")
            labels.textFontSize = NSExpression(forConstantValue: NSNumber(value: 11))
            labels.textColor = NSExpression(forConstantValue: UIColor(red: 0.4, green: 0.25, blue: 0.1, alpha: 1.0))
            labels.textHaloColor = NSExpression(forConstantValue: UIColor.white.withAlphaComponent(0.9))
            labels.textHaloWidth = NSExpression(forConstantValue: NSNumber(value: 1.5))
            labels.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: 1.2)))
            labels.textAnchor = NSExpression(forConstantValue: "top")
            labels.textAllowsOverlap = NSExpression(forConstantValue: false)
            labels.minimumZoomLevel = 11
            style.addLayer(labels)
        }

        // MARK: - Track Overlay (Shape Source + Line Layer for reliability)

        private static let trackSourceId = "user-track-source"
        private static let trackLayerId = "user-track-layer"

        func syncTrackOverlay(mapView: MLNMapView, style: MLNStyle, recorder: TrackRecorder) {
            // Remove annotation-based fallback if it exists
            if let existing = trackAnnotation {
                mapView.removeAnnotation(existing)
                trackAnnotation = nil
            }

            // Use Kalman-filtered coordinates for smooth display, fall back to raw
            var coords = recorder.smoothedCoordinates.count > 1
                ? recorder.smoothedCoordinates
                : recorder.currentTrack?.coordinates ?? []

            guard coords.count > 1 else {
                // No track: remove source/layer if present
                if let layer = style.layer(withIdentifier: Self.trackLayerId) {
                    style.removeLayer(layer)
                }
                if let source = style.source(withIdentifier: Self.trackSourceId) {
                    style.removeSource(source)
                }
                return
            }

            let polyline = MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count))

            if let existingSource = style.source(withIdentifier: Self.trackSourceId) as? MLNShapeSource {
                // Update existing source data (efficient — no remove/add)
                existingSource.shape = polyline
            } else {
                // Create source + layer for the first time
                let source = MLNShapeSource(identifier: Self.trackSourceId, shape: polyline, options: nil)
                style.addSource(source)

                let layer = MLNLineStyleLayer(identifier: Self.trackLayerId, source: source)
                layer.lineColor = NSExpression(forConstantValue: UIColor.systemRed)
                layer.lineWidth = NSExpression(forConstantValue: NSNumber(value: 3.0))
                layer.lineJoin = NSExpression(forConstantValue: "round")
                layer.lineCap = NSExpression(forConstantValue: "round")
                style.addLayer(layer)
            }
        }

        /// Fallback: annotation-based track overlay (used before style loads)
        func syncTrackOverlayAnnotation(mapView: MLNMapView, recorder: TrackRecorder) {
            if let existing = trackAnnotation {
                mapView.removeAnnotation(existing)
                trackAnnotation = nil
            }

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
            print("🐾 syncPetAnnotation: \(visiblePets.count) visible pets, \(tractive.pets.count) total")
            for p in tractive.pets {
                print("🐾   \(p.name): visible=\(p.isVisible), hasPos=\(p.position != nil)")
            }
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
