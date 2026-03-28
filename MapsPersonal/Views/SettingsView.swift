import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    var tractive: TractiveService
    @Bindable var mapState: MapState
    @State private var profile = UserProfile()
    @State private var useCustomMaxHR = false
    @State private var customMaxHR = 160
    @State private var tractiveEmail = TractiveCredentials.email ?? ""
    @State private var tractivePassword = TractiveCredentials.password ?? ""
    @State private var tractiveStatus = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Personal Data
                Section("Personal Data") {
                    OptionalStepper(label: "Age", unit: "", value: binding(\.age), range: 10...120, step: 1, format: "%.0f")
                    OptionalStepper(label: "Weight", unit: "kg", value: binding(\.weightKg), range: 30...200, step: 0.5, format: "%.1f")
                    OptionalStepper(label: "Height", unit: "m", value: binding(\.heightM), range: 1.0...2.5, step: 0.01, format: "%.2f")
                    OptionalStepper(label: "Waist", unit: "cm", value: binding(\.waistCm), range: 50...200, step: 0.5, format: "%.1f")
                }

                // MARK: - Track Recording
                Section {
                    Toggle("Auto-save to iCloud", isOn: $profile.autoSaveICloud)

                    Stepper("Temp interval: \(profile.tempIntervalMinutes) min",
                            value: $profile.tempIntervalMinutes, in: 1...30)

                    Stepper("Temp elev. threshold: \(profile.tempElevationThreshold) m",
                            value: $profile.tempElevationThreshold, in: 50...500, step: 50)
                } header: {
                    Text("Track Recording")
                } footer: {
                    Text("Temperature is recorded from Open-Meteo weather forecast at the configured interval or when cumulative elevation change exceeds the threshold.")
                        .font(.caption2)
                }

                // MARK: - Map
                Section {
                    Picker("Base Layer", selection: $mapState.activeBaseLayer) {
                        ForEach(MapLayer.baseLayers.filter { $0.tileURLTemplate != nil }) { layer in
                            Text(layer.displayName).tag(layer)
                        }
                    }

                    Toggle("Peaks (OSM)", isOn: $mapState.showPeaks)

                    Toggle("Hillshade", isOn: $mapState.showHillshade)
                    if mapState.showHillshade {
                        HStack {
                            Text("Opacity")
                                .font(.caption)
                            Slider(value: $mapState.hillshadeOpacity, in: 0.1...1.0, step: 0.1)
                            Text(String(format: "%.0f%%", mapState.hillshadeOpacity * 100))
                                .font(.caption)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }

                    Toggle("Contour Lines", isOn: $mapState.showContours)
                    if mapState.showContours {
                        HStack {
                            Text("Opacity")
                                .font(.caption)
                            Slider(value: $mapState.contourOpacity, in: 0.1...1.0, step: 0.1)
                            Text(String(format: "%.0f%%", mapState.contourOpacity * 100))
                                .font(.caption)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                } header: {
                    Text("Map")
                }

                // MARK: - Heart Rate
                if profile.age != nil {
                    Section {
                        if let calcHR = profile.calculatedMaxHR {
                            HStack {
                                Text("Calculated Max HR")
                                Spacer()
                                Text("\(calcHR) bpm")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Toggle("Custom Max HR", isOn: $useCustomMaxHR)
                            .onChange(of: useCustomMaxHR) { _, newValue in
                                profile.maxHROverride = newValue ? customMaxHR : nil
                            }

                        if useCustomMaxHR {
                            Stepper("Max HR: \(customMaxHR) bpm",
                                    value: $customMaxHR, in: 100...220)
                                .onChange(of: customMaxHR) { _, newValue in
                                    profile.maxHROverride = newValue
                                }
                        }
                    } header: {
                        Text("Heart Rate")
                    } footer: {
                        Text("Tanaka et al. (2001): HRmax = 208 − 0.7 × age")
                            .font(.caption2)
                    }

                    // MARK: - HR Zones
                    if let maxHR = profile.maxHR {
                        Section {
                            ForEach(Array(profile.zones.enumerated()), id: \.offset) { index, zone in
                                HStack {
                                    Text("Z\(index + 1)")
                                        .font(.headline)
                                        .foregroundStyle(zoneColor(index))
                                        .frame(width: 30)
                                    Text(zone.name)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text("\(zone.minPct)–\(zone.maxPct)%")
                                        .foregroundStyle(.secondary)
                                    Text("\(zone.bpmRange(maxHR: maxHR).lowerBound)–\(zone.bpmRange(maxHR: maxHR).upperBound)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 65, alignment: .trailing)
                                }
                            }
                        } header: {
                            Text("HR Zones (Max HR: \(maxHR) bpm)")
                        }
                    }
                }

                // MARK: - Body Metrics
                if profile.bmi != nil || profile.bri != nil {
                    Section("Body Metrics") {
                        if let bmi = profile.bmi {
                            HStack {
                                Text("BMI")
                                Spacer()
                                Text(String(format: "%.1f", bmi))
                                    .foregroundStyle(bmiColor(bmi))
                            }
                        }
                        if let bri = profile.bri {
                            HStack {
                                Text("BRI")
                                Spacer()
                                Text(String(format: "%.1f", bri))
                                    .foregroundStyle(briColor(bri))
                            }
                        }
                    }
                }
                // MARK: - Tractive Pet Tracker
                Section {
                    TextField("Email", text: $tractiveEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    SecureField("Password", text: $tractivePassword)
                        .textContentType(.password)

                    Button(tractiveStatus.isEmpty ? "Save & Connect" : tractiveStatus) {
                        TractiveCredentials.email = tractiveEmail
                        TractiveCredentials.password = tractivePassword
                        tractiveStatus = "Saved"
                    }
                    .disabled(tractiveEmail.isEmpty || tractivePassword.isEmpty)

                    if TractiveCredentials.hasCredentials {
                        Button("Clear Credentials", role: .destructive) {
                            TractiveCredentials.clear()
                            tractiveEmail = ""
                            tractivePassword = ""
                            tractiveStatus = ""
                        }
                    }
                } header: {
                    Text("Tractive Pet Tracker")
                } footer: {
                    Text("Credentials are stored securely in the device Keychain. Restart the app after saving to connect.")
                        .font(.caption2)
                }

                // MARK: - Pets (discovered from Tractive)
                if tractive.isConnected && !tractive.pets.isEmpty {
                    Section {
                        ForEach(tractive.pets) { pet in
                            HStack {
                                Text(pet.emoji)
                                    .font(.title2)
                                Text(pet.name)
                                    .font(.body)

                                Spacer()

                                if let battery = pet.batteryLevel {
                                    HStack(spacing: 2) {
                                        Image(systemName: batteryIcon(level: battery, charging: pet.isCharging))
                                            .foregroundStyle(batteryColor(battery))
                                            .font(.caption)
                                        Text("\(battery)%")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Toggle("", isOn: Binding(
                                    get: { pet.isVisible },
                                    set: { _ in tractive.togglePet(pet.id) }
                                ))
                                .labelsHidden()
                            }
                        }
                    } header: {
                        Text("Pets")
                    } footer: {
                        Text("Toggle visibility on the map. Pets with LIVE tracking enabled during hike recording update every few seconds.")
                            .font(.caption2)
                    }
                }

                // MARK: - About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("\(appVersion) (\(buildNumber))")
                            .foregroundStyle(.secondary)
                    }

                    NavigationLink("Credits") {
                        creditsView
                    }

                    Button("Reset Map to Defaults") {
                        mapState.resetToDefaults()
                    }
                    .foregroundStyle(.red)
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if let override = profile.maxHROverride {
                    useCustomMaxHR = true
                    customMaxHR = override
                }
            }
        }
    }

    // MARK: - About Helpers

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    private var creditsView: some View {
        List {
            Section("Map Engine") {
                creditRow("MapLibre Native", "BSD-2-Clause", "maplibre.org")
            }
            Section("Map Data") {
                creditRow("OpenStreetMap", "ODbL", "openstreetmap.org")
                creditRow("ESRI World Imagery", "Esri License", "arcgis.com")
                creditRow("IGN Spain (MTN/PNOA)", "CC BY 4.0", "ign.es")
                creditRow("IGME Geological", "CC BY 4.0", "igme.es")
                creditRow("MapTiler Terrain", "MapTiler License", "maptiler.com")
            }
            Section("Services") {
                creditRow("Open-Meteo", "CC BY 4.0", "open-meteo.com")
                creditRow("Nominatim / OSM", "ODbL", "nominatim.org")
                creditRow("Overpass API", "ODbL", "overpass-api.de")
                creditRow("Tractive", "Commercial", "tractive.com")
                creditRow("Apple HealthKit", "Apple", "developer.apple.com")
            }
            Section("Development") {
                creditRow("Claude Code", "Anthropic", "claude.ai/code")
                creditRow("Xcode / Swift / SwiftUI", "Apple", "developer.apple.com")
            }
        }
        .navigationTitle("Credits")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func creditRow(_ name: String, _ license: String, _ url: String) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(license)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func binding(_ keyPath: ReferenceWritableKeyPath<UserProfile, Double?>) -> Binding<Double?> {
        Binding(
            get: { profile[keyPath: keyPath] },
            set: { profile[keyPath: keyPath] = $0 }
        )
    }

    private func binding(_ keyPath: ReferenceWritableKeyPath<UserProfile, Int?>) -> Binding<Double?> {
        Binding(
            get: { profile[keyPath: keyPath].map(Double.init) },
            set: { profile[keyPath: keyPath] = $0.map(Int.init) }
        )
    }

    private func zoneColor(_ index: Int) -> Color {
        switch index {
        case 0: return .blue
        case 1: return .green
        case 2: return .yellow
        case 3: return .orange
        case 4: return .red
        default: return .gray
        }
    }

    private func batteryIcon(level: Int, charging: Bool) -> String {
        if charging { return "battery.100.bolt" }
        switch level {
        case 0..<15: return "battery.0"
        case 15..<40: return "battery.25"
        case 40..<60: return "battery.50"
        case 60..<85: return "battery.75"
        default: return "battery.100"
        }
    }

    private func batteryColor(_ level: Int) -> Color {
        switch level {
        case 0..<20: return .red
        case 20..<50: return .orange
        default: return .green
        }
    }

    private func bmiColor(_ bmi: Double) -> Color {
        switch bmi {
        case ..<18.5: return .blue
        case ...25: return .green
        case ..<30: return .orange
        default: return .red
        }
    }

    private func briColor(_ bri: Double) -> Color {
        switch bri {
        case ..<3.5: return .green
        case ..<6.9: return .yellow
        default: return .red
        }
    }
}

// MARK: - Optional Stepper

private struct OptionalStepper: View {
    let label: String
    let unit: String
    @Binding var value: Double?
    let range: ClosedRange<Double>
    let step: Double
    let format: String

    var body: some View {
        HStack {
            if let val = value {
                Stepper(
                    "\(label): \(String(format: format, val)) \(unit)",
                    value: Binding(
                        get: { val },
                        set: { value = $0 }
                    ),
                    in: range,
                    step: step
                )
                Button {
                    value = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
            } else {
                Text("\(label)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Set") {
                    // Start at midpoint of range
                    value = (range.lowerBound + range.upperBound) / 2
                }
                .font(.caption)
            }
        }
    }
}
