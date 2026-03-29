import Foundation

// MARK: - Heart Rate Zone

struct HeartRateZone: Codable, Identifiable {
    var id: String { name }
    var name: String
    var minPct: Int
    var maxPct: Int

    func bpmRange(maxHR: Int) -> ClosedRange<Int> {
        let lo = Int(Double(minPct) * Double(maxHR) / 100.0)
        let hi = Int(Double(maxPct) * Double(maxHR) / 100.0)
        return min(lo, hi)...max(lo, hi)
    }
}

// MARK: - User Profile

@Observable
class UserProfile {
    var age: Int? {
        didSet { save() }
    }
    var weightKg: Double? {
        didSet { save() }
    }
    var heightM: Double? {
        didSet { save() }
    }
    var waistCm: Double? {
        didSet { save() }
    }
    var maxHROverride: Int? {
        didSet { save() }
    }
    var zones: [HeartRateZone] {
        didSet { save() }
    }

    // MARK: - Track Recording Settings

    /// Auto-save track to iCloud when saving
    var autoSaveICloud: Bool {
        didSet { save() }
    }
    /// Temperature recording interval in minutes
    var tempIntervalMinutes: Int {
        didSet { save() }
    }
    /// Temperature recording elevation threshold in meters
    var tempElevationThreshold: Int {
        didSet { save() }
    }

    // Tanaka et al. (2001): HRmax = 208 - 0.7 * age
    var calculatedMaxHR: Int? {
        guard let age else { return nil }
        return Int((208.0 - 0.7 * Double(age)).rounded())
    }

    var maxHR: Int? {
        maxHROverride ?? calculatedMaxHR
    }

    // BMI = weight / height^2
    var bmi: Double? {
        guard let w = weightKg, let h = heightM, h > 0 else { return nil }
        return w / (h * h)
    }

    // BRI = 364.2 - 365.5 * sqrt(1 - (waist / (height * π))^2)
    var bri: Double? {
        guard let waist = waistCm, let height = heightM, height > 0 else { return nil }
        let waistM = waist / 100.0
        let ratio = waistM / (height * .pi)
        let squared = ratio * ratio
        guard squared < 1 else { return nil }
        let eccentricity = sqrt(1 - squared)
        return 364.2 - 365.5 * eccentricity
    }

    /// Returns the zone index (0-based) and zone for the given BPM, or nil if below Z1
    func zone(for bpm: Int) -> (index: Int, zone: HeartRateZone)? {
        guard let maxHR else { return nil }
        for (i, z) in zones.enumerated() {
            let range = z.bpmRange(maxHR: maxHR)
            if range.contains(bpm) {
                return (i, z)
            }
        }
        // Above max zone
        if let last = zones.last, bpm > last.bpmRange(maxHR: maxHR).upperBound {
            return (zones.count - 1, last)
        }
        return nil
    }

    static let zoneColors: [String] = ["blue", "green", "yellow", "orange", "red"]

    static let defaultZones: [HeartRateZone] = [
        HeartRateZone(name: "Recovery", minPct: 50, maxPct: 60),
        HeartRateZone(name: "Aerobic", minPct: 60, maxPct: 70),
        HeartRateZone(name: "Tempo", minPct: 70, maxPct: 80),
        HeartRateZone(name: "Threshold", minPct: 80, maxPct: 90),
        HeartRateZone(name: "Maximum", minPct: 90, maxPct: 100),
    ]

    init() {
        let d = UserDefaults.standard

        // Try loading from iCloud profile.json first (synced from Control Center)
        var icloudProfile: [String: Any]?
        if let container = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.jorge.mapspersonal2026") {
            let profileURL = container.appendingPathComponent("Documents/profile.json")
            if let data = try? Data(contentsOf: profileURL),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                icloudProfile = json
                print("UserProfile: loaded from iCloud profile.json")
            }
        }

        // iCloud values override UserDefaults (if present)
        let p = icloudProfile

        if let age = p?["age"] as? Int {
            self.age = age
        } else {
            self.age = d.object(forKey: "profile.age") != nil ? d.integer(forKey: "profile.age") : nil
        }

        if let w = p?["weightKg"] as? Double {
            self.weightKg = w
        } else {
            self.weightKg = d.object(forKey: "profile.weightKg") != nil ? d.double(forKey: "profile.weightKg") : nil
        }

        if let h = p?["heightM"] as? Double {
            self.heightM = h
        } else {
            self.heightM = d.object(forKey: "profile.heightM") != nil ? d.double(forKey: "profile.heightM") : nil
        }

        if let w = p?["waistCm"] as? Double {
            self.waistCm = w
        } else {
            self.waistCm = d.object(forKey: "profile.waistCm") != nil ? d.double(forKey: "profile.waistCm") : nil
        }

        if let override = p?["maxHROverride"] as? Int {
            self.maxHROverride = override
        } else if d.object(forKey: "profile.maxHROverride") != nil {
            self.maxHROverride = d.integer(forKey: "profile.maxHROverride")
        } else {
            self.maxHROverride = nil
        }

        if let zonesArray = p?["zones"] as? [[String: Any]] {
            let parsed = zonesArray.compactMap { dict -> HeartRateZone? in
                guard let name = dict["name"] as? String,
                      let minPct = dict["minPct"] as? Int,
                      let maxPct = dict["maxPct"] as? Int else { return nil }
                return HeartRateZone(name: name, minPct: minPct, maxPct: maxPct)
            }
            self.zones = parsed.isEmpty ? Self.defaultZones : parsed
        } else if let data = d.data(forKey: "profile.zones"),
           let decoded = try? JSONDecoder().decode([HeartRateZone].self, from: data) {
            self.zones = decoded
        } else {
            self.zones = Self.defaultZones
        }

        // Track recording settings
        if let auto = p?["autoSaveICloud"] as? Bool {
            self.autoSaveICloud = auto
        } else {
            self.autoSaveICloud = d.object(forKey: "track.autoSaveICloud") != nil
                ? d.bool(forKey: "track.autoSaveICloud") : false
        }

        if let interval = p?["tempIntervalMinutes"] as? Int {
            self.tempIntervalMinutes = interval
        } else {
            self.tempIntervalMinutes = d.object(forKey: "track.tempIntervalMinutes") != nil
                ? d.integer(forKey: "track.tempIntervalMinutes") : 5
        }

        if let threshold = p?["tempElevationThreshold"] as? Int {
            self.tempElevationThreshold = threshold
        } else {
            self.tempElevationThreshold = d.object(forKey: "track.tempElevationThreshold") != nil
                ? d.integer(forKey: "track.tempElevationThreshold") : 100
        }

        // Persist iCloud values to UserDefaults so they survive even without iCloud
        if p != nil { save() }
    }

    private func save() {
        let d = UserDefaults.standard

        if let age { d.set(age, forKey: "profile.age") }
        else { d.removeObject(forKey: "profile.age") }

        if let weightKg { d.set(weightKg, forKey: "profile.weightKg") }
        else { d.removeObject(forKey: "profile.weightKg") }

        if let heightM { d.set(heightM, forKey: "profile.heightM") }
        else { d.removeObject(forKey: "profile.heightM") }

        if let waistCm { d.set(waistCm, forKey: "profile.waistCm") }
        else { d.removeObject(forKey: "profile.waistCm") }

        if let override = maxHROverride {
            d.set(override, forKey: "profile.maxHROverride")
        } else {
            d.removeObject(forKey: "profile.maxHROverride")
        }

        if let data = try? JSONEncoder().encode(zones) {
            d.set(data, forKey: "profile.zones")
        }

        d.set(autoSaveICloud, forKey: "track.autoSaveICloud")
        d.set(tempIntervalMinutes, forKey: "track.tempIntervalMinutes")
        d.set(tempElevationThreshold, forKey: "track.tempElevationThreshold")
    }
}
