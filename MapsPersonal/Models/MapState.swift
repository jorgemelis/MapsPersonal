import Foundation
import CoreLocation
import SwiftUI

// MARK: - Map State

@Observable
class MapState {
    var activeBaseLayer: MapLayer = .ignMTN {
        didSet { save() }
    }
    var activeOverlays: Set<MapLayer> = [] {
        didSet { save() }
    }
    var overlayOpacity: [MapLayer: Double] = [.igmeGeological: 0.6, .igmeGeologicalOffline: 0.6] {
        didSet { save() }
    }

    // URLs for offline tile servers (set at runtime, not persisted)
    var offlineTileURLs: [MapLayer: String] = [:]

    // Dynamic offline layers from OfflineMapsManager (mapId -> urlTemplate)
    var dynamicOfflineLayers: [String: String] = [:]
    var activeDynamicOverlays: Set<String> = [] {
        didSet { save() }
    }
    var dynamicOverlayOpacity: [String: Double] = [:] {
        didSet { save() }
    }

    // Terrain overlays
    var showHillshade = false {
        didSet { save(); terrainVersion += 1 }
    }
    var hillshadeOpacity: Double = 0.5 {
        didSet { save(); terrainVersion += 1 }
    }
    var showContours = false {
        didSet { save(); terrainVersion += 1 }
    }
    var contourOpacity: Double = 0.6 {
        didSet { save(); terrainVersion += 1 }
    }
    var showPeaks = false {
        didSet { save(); terrainVersion += 1 }
    }
    var terrainVersion: Int = 0

    var isRecordingTrack = false
    var currentTrack: GPXTrack?
    var savedTracks: [GPXTrack] = []

    var showsUserLocation = true
    var isFollowingUser = true
    var resetNorthRequest = false
    var flyToCoordinate: CLLocationCoordinate2D?  // set to fly map to a location

    var centerCoordinate = CLLocationCoordinate2D(latitude: 40.4168, longitude: -3.7038) {
        didSet { scheduleCameraSave() }
    }
    var zoomLevel: Double = 6.0 {
        didSet { scheduleCameraSave() }
    }
    var bearing: Double = 0.0 {
        didSet { scheduleCameraSave() }
    }
    var pitch: Double = 0.0 {
        didSet { scheduleCameraSave() }
    }

    private static let defaults = UserDefaults.standard
    private var isSaving = false
    private var cameraSaveTask: Task<Void, Never>?

    init() {
        restore()
    }

    // MARK: - Layer visibility helpers

    func isLayerVisible(_ layer: MapLayer) -> Bool {
        switch layer.category {
        case .base: return activeBaseLayer == layer
        case .overlay: return activeOverlays.contains(layer)
        }
    }

    func toggleOverlay(_ layer: MapLayer) {
        if activeOverlays.contains(layer) {
            activeOverlays.remove(layer)
        } else {
            activeOverlays.insert(layer)
        }
    }

    func opacityFor(_ layer: MapLayer) -> Double {
        overlayOpacity[layer] ?? 1.0
    }

    /// Reset all settings to defaults
    func resetToDefaults() {
        isSaving = true
        activeBaseLayer = .ignMTN
        activeOverlays = []
        overlayOpacity = [.igmeGeological: 0.6, .igmeGeologicalOffline: 0.6]
        activeDynamicOverlays = []
        dynamicOverlayOpacity = [:]
        centerCoordinate = CLLocationCoordinate2D(latitude: 40.4168, longitude: -3.7038)
        zoomLevel = 6.0
        bearing = 0.0
        pitch = 0.0
        showHillshade = false
        hillshadeOpacity = 0.5
        showContours = false
        contourOpacity = 0.6
        showPeaks = false
        isSaving = false

        // Clear all saved state
        let d = Self.defaults
        for key in ["map.baseLayer", "map.overlays", "map.overlayOpacity",
                     "map.dynamicOverlays", "map.dynamicOverlayOpacity",
                     "map.lat", "map.lon", "map.zoom",
                     "map.bearing", "map.pitch",
                     "map.showHillshade", "map.hillshadeOpacity",
                     "map.showContours", "map.contourOpacity"] {
            d.removeObject(forKey: key)
        }
    }

    // MARK: - Persistence

    private func scheduleCameraSave() {
        cameraSaveTask?.cancel()
        cameraSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self.saveCamera()
        }
    }

    private func saveCamera() {
        let d = Self.defaults
        d.set(centerCoordinate.latitude, forKey: "map.lat")
        d.set(centerCoordinate.longitude, forKey: "map.lon")
        d.set(zoomLevel, forKey: "map.zoom")
        d.set(bearing, forKey: "map.bearing")
        d.set(pitch, forKey: "map.pitch")
    }

    private func save() {
        guard !isSaving else { return }
        let d = Self.defaults
        d.set(activeBaseLayer.rawValue, forKey: "map.baseLayer")
        d.set(Array(activeOverlays.map { $0.rawValue }), forKey: "map.overlays")

        // Overlay opacity: [String: Double]
        var opacityDict: [String: Double] = [:]
        for (layer, val) in overlayOpacity { opacityDict[layer.rawValue] = val }
        d.set(opacityDict, forKey: "map.overlayOpacity")

        // Dynamic overlays
        d.set(Array(activeDynamicOverlays), forKey: "map.dynamicOverlays")
        d.set(dynamicOverlayOpacity, forKey: "map.dynamicOverlayOpacity")

        // Terrain overlays
        d.set(showHillshade, forKey: "map.showHillshade")
        d.set(hillshadeOpacity, forKey: "map.hillshadeOpacity")
        d.set(showContours, forKey: "map.showContours")
        d.set(contourOpacity, forKey: "map.contourOpacity")
        d.set(showPeaks, forKey: "map.showPeaks")
    }

    private func restore() {
        isSaving = true
        defer { isSaving = false }

        let d = Self.defaults

        if let base = d.string(forKey: "map.baseLayer"),
           let layer = MapLayer(rawValue: base) {
            activeBaseLayer = layer
        }

        if let overlays = d.stringArray(forKey: "map.overlays") {
            activeOverlays = Set(overlays.compactMap { MapLayer(rawValue: $0) })
        }

        if let opacityDict = d.dictionary(forKey: "map.overlayOpacity") as? [String: Double] {
            overlayOpacity = [:]
            for (key, val) in opacityDict {
                if let layer = MapLayer(rawValue: key) {
                    overlayOpacity[layer] = val
                }
            }
        }

        if let dynOverlays = d.stringArray(forKey: "map.dynamicOverlays") {
            activeDynamicOverlays = Set(dynOverlays)
        }

        if let dynOpacity = d.dictionary(forKey: "map.dynamicOverlayOpacity") as? [String: Double] {
            dynamicOverlayOpacity = dynOpacity
        }

        let lat = d.double(forKey: "map.lat")
        let lon = d.double(forKey: "map.lon")
        let zoom = d.double(forKey: "map.zoom")

        if lat != 0 || lon != 0 {
            centerCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        if zoom > 0 {
            zoomLevel = zoom
        }

        bearing = d.double(forKey: "map.bearing")
        pitch = d.double(forKey: "map.pitch")

        // Terrain overlays
        showHillshade = d.bool(forKey: "map.showHillshade")
        if d.object(forKey: "map.hillshadeOpacity") != nil {
            hillshadeOpacity = d.double(forKey: "map.hillshadeOpacity")
        }
        showContours = d.bool(forKey: "map.showContours")
        if d.object(forKey: "map.contourOpacity") != nil {
            contourOpacity = d.double(forKey: "map.contourOpacity")
        }
        showPeaks = d.bool(forKey: "map.showPeaks")
    }
}
