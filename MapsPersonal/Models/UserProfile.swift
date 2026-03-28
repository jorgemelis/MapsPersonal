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

    static let defaultZones: [HeartRateZone] = [
        HeartRateZone(name: "Recovery", minPct: 50, maxPct: 60),
        HeartRateZone(name: "Aerobic", minPct: 60, maxPct: 70),
        HeartRateZone(name: "Tempo", minPct: 70, maxPct: 80),
        HeartRateZone(name: "Threshold", minPct: 80, maxPct: 90),
        HeartRateZone(name: "Maximum", minPct: 90, maxPct: 100),
    ]

    init() {
        let d = UserDefaults.standard

        self.age = d.object(forKey: "profile.age") != nil ? d.integer(forKey: "profile.age") : nil
        self.weightKg = d.object(forKey: "profile.weightKg") != nil ? d.double(forKey: "profile.weightKg") : nil
        self.heightM = d.object(forKey: "profile.heightM") != nil ? d.double(forKey: "profile.heightM") : nil
        self.waistCm = d.object(forKey: "profile.waistCm") != nil ? d.double(forKey: "profile.waistCm") : nil

        if d.object(forKey: "profile.maxHROverride") != nil {
            self.maxHROverride = d.integer(forKey: "profile.maxHROverride")
        } else {
            self.maxHROverride = nil
        }

        if let data = d.data(forKey: "profile.zones"),
           let decoded = try? JSONDecoder().decode([HeartRateZone].self, from: data) {
            self.zones = decoded
        } else {
            self.zones = Self.defaultZones
        }
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
    }
}
