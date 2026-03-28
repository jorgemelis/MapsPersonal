import SwiftUI

// MARK: - Help View

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    FeatureRow(
                        icon: "square.3.layers.3d",
                        color: .blue,
                        title: "Map Layers",
                        description: "Switch between topographic, satellite, and street maps. Available layers depend on your region (Spain: IGN Topo, IGN Ortofoto; worldwide: OSM, ESRI Satellite)."
                    )

                    FeatureRow(
                        icon: "map.fill",
                        color: .brown,
                        title: "Geological Maps",
                        description: "Overlay geological maps on top of any base layer. Currently available: IGME 50k (Spain). Can also be downloaded for offline use."
                    )

                    FeatureRow(
                        icon: "arrow.down.circle",
                        color: .green,
                        title: "Offline Maps",
                        description: "Download map tiles (MBTiles) for areas without cell coverage. Access from ⋯ → Offline Maps."
                    )
                } header: {
                    Text("Maps")
                }

                Section {
                    FeatureRow(
                        icon: "record.circle",
                        color: .red,
                        title: "Track Recording",
                        description: "Record GPS tracks with elevation, speed, and distance stats. Export as GPX to share with Strava, Garmin, etc."
                    )

                    FeatureRow(
                        icon: "point.topleft.down.to.point.bottomright.curvepath",
                        color: .orange,
                        title: "Saved Tracks",
                        description: "View and manage your recorded tracks. Access from ⋯ → Saved Tracks."
                    )

                    FeatureRow(
                        icon: "heart.fill",
                        color: .red,
                        title: "Heart Rate Zones",
                        description: "Configure your HR zones in Settings based on age (Tanaka formula) or a custom max HR. Requires Apple Watch for live tracking (coming soon)."
                    )
                } header: {
                    Text("Tracking & Fitness")
                }

                Section {
                    FeatureRow(
                        icon: "pawprint.fill",
                        color: .orange,
                        title: "Pet Tracker (Tractive)",
                        description: "See your pets' live location on the map. Requires a Tractive GPS tracker. Enter your Tractive credentials in Settings."
                    )
                } header: {
                    Text("Pets")
                }

                Section {
                    FeatureRow(
                        icon: "checklist",
                        color: .green,
                        title: "Checklists",
                        description: "Create packing lists, shopping lists, or gear checklists. Syncs via iCloud between iPhone and iPad. Stored as Markdown — editable from your Mac too."
                    )

                    FeatureRow(
                        icon: "cloud.sun.fill",
                        color: .yellow,
                        title: "Weather",
                        description: "Live weather with 24h forecast, UV index, precipitation, and wind. Automatically fetched for your current location."
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("UV Index Guide (WHO)")
                            .font(.subheadline.weight(.semibold))
                        UVRow(range: "0 – 2", risk: "Low", action: "No protection needed", color: .green)
                        UVRow(range: "3 – 5", risk: "Moderate", action: "Sunscreen on exposed skin", color: .red)
                        UVRow(range: "6 – 7", risk: "High", action: "Sunscreen + hat + sunglasses", color: .red)
                        UVRow(range: "8 – 10", risk: "Very high", action: "Avoid prolonged exposure", color: .red)
                        UVRow(range: "11+", risk: "Extreme", action: "Stay in shade", color: .red)
                        Text("UPF clothing protects covered areas, but face, neck and hands still need sunscreen at UV ≥ 3.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                    .padding(.vertical, 2)

                    FeatureRow(
                        icon: "mountain.2.fill",
                        color: .gray,
                        title: "Hillshade & Contours",
                        description: "Toggle terrain visualization in the layer picker. Hillshade shows relief, contour lines show elevation."
                    )
                } header: {
                    Text("Tools")
                }

                Section {
                    FeatureRow(
                        icon: "gearshape",
                        color: .gray,
                        title: "Settings",
                        description: "Configure your profile (age, weight, height), HR zones, Tractive credentials, and body metrics (BMI, BRI)."
                    )
                } header: {
                    Text("Configuration")
                }
            }
            .navigationTitle("Features")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Feature Row

private struct UVRow: View {
    let range: String
    let risk: String
    let action: String
    let color: Color

    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(range)
                .font(.caption.monospaced())
                .frame(width: 44, alignment: .leading)
            Text(risk)
                .font(.caption.weight(.medium))
                .frame(width: 70, alignment: .leading)
            Text(action)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
