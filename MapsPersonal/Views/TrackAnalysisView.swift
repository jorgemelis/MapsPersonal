import SwiftUI
import Charts
import CoreLocation

// MARK: - Track Analysis View

struct TrackAnalysisView: View {
    let track: GPXTrack
    @State private var localities: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                statsGrid
                elevationChart
                splitsSection
                speedChart
                if track.hasHeartRate { heartRateChart }
                if track.hasSensorData { sensorSection }
            }
            .padding()
        }
        .navigationTitle("Análisis")
        .navigationBarTitleDisplayMode(.inline)
        .task { await resolveLocalities() }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(track.name)
                .font(.headline)
            if !localities.isEmpty {
                Text(localities.joined(separator: " → "))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
            HStack(spacing: 12) {
                Text(formattedDate(track.startDate))
                    .foregroundStyle(.secondary)
                if track.hasHeartRate {
                    Label("HR", systemImage: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if track.hasSensorData {
                    Label("Sensor", systemImage: "sensor.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .font(.subheadline)
        }
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            statCell("Distancia", formatDistance(track.totalDistance))
            statCell("Duración", formatDuration(track.duration))
            statCell("En movimiento", formatDuration(track.movingTime))
            statCell("Parado", formatDuration(track.stoppedTime))
            statCell("Vel. media", formatSpeed(track.averageMovingSpeed))
            statCell("Vel. total", formatSpeed(track.averageSpeed))
            statCell("Desnivel +", formatElevation(track.elevationGain))
            statCell("Desnivel -", formatElevation(track.elevationLoss))
            statCell("Alt. mín", formatElevation(track.minElevation))
            statCell("Alt. máx", formatElevation(track.maxElevation))
            if let avgHR = track.averageHeartRate {
                statCell("FC media", "\(avgHR) bpm")
            }
            if let maxHR = track.maxHeartRate {
                statCell("FC máx", "\(maxHR) bpm")
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func statCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.body, design: .monospaced, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Elevation Chart

    private var elevationChart: some View {
        let profile = track.elevationProfile
        guard profile.count > 2 else { return AnyView(EmptyView()) }

        let sampled = sampleArray(profile, maxPoints: 300)
        let elevations = sampled.map(\.elevation)
        let minEle = elevations.min() ?? 0
        let maxEle = elevations.max() ?? 0
        let margin = max((maxEle - minEle) * 0.05, 5)

        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
                Text("Perfil de elevación")
                    .font(.headline)

                Chart(sampled.indices, id: \.self) { i in
                    let km = sampled[i].distance / 1000
                    let ele = sampled[i].elevation

                    AreaMark(
                        x: .value("km", km),
                        yStart: .value("base", minEle),
                        yEnd: .value("m", ele)
                    )
                    .foregroundStyle(.green.opacity(0.2))

                    LineMark(
                        x: .value("km", km),
                        y: .value("m", ele)
                    )
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                .chartYScale(domain: (minEle - margin)...(maxEle + margin))
                .chartXAxisLabel("km")
                .chartYAxisLabel("m")
                .frame(height: 200)
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        )
    }

    // MARK: - Splits

    private var splitsSection: some View {
        let splits = track.splits
        guard !splits.isEmpty else { return AnyView(EmptyView()) }

        let fastestPace = splits.map(\.pace).filter { $0 > 0 }.min() ?? 1
        let slowestPace = splits.map(\.pace).filter { $0 > 0 }.max() ?? 1

        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
                Text("Splits por km")
                    .font(.headline)

                ForEach(splits) { split in
                    HStack(spacing: 6) {
                        // KM number
                        Text(split.isPartial
                             ? String(format: ".%0.f", split.partialMeters / 100)
                             : "\(split.km)")
                            .frame(width: 24, alignment: .trailing)
                            .foregroundStyle(.secondary)

                        // Pace bar — full width, colored by relative pace
                        GeometryReader { geo in
                            let range = slowestPace - fastestPace
                            let normalized = range > 0
                                ? (split.pace - fastestPace) / range
                                : 0.5
                            RoundedRectangle(cornerRadius: 3)
                                .fill(paceColor(1.0 - normalized))
                                .frame(width: geo.size.width)
                        }
                        .frame(height: 18)

                        // Pace
                        Text(formatPace(split.pace))
                            .frame(width: 45, alignment: .trailing)

                        // Elevation change
                        Text(String(format: "%+.0f", split.elevationChange))
                            .frame(width: 40, alignment: .trailing)
                            .foregroundStyle(split.elevationChange >= 0 ? .green : .red)
                    }
                    .font(.system(.caption, design: .monospaced))
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        )
    }

    // MARK: - Speed Chart

    private var speedChart: some View {
        let speeds = track.smoothedSpeeds
        guard speeds.count > 2 else { return AnyView(EmptyView()) }

        let sampled = sampleArray(speeds, maxPoints: 300)
        let speedValues = sampled.map(\.speed)
        let maxSpeed = speedValues.max() ?? 10

        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
                Text("Velocidad")
                    .font(.headline)

                Chart(sampled.indices, id: \.self) { i in
                    let km = sampled[i].distance / 1000
                    let spd = sampled[i].speed

                    AreaMark(
                        x: .value("km", km),
                        yStart: .value("base", 0.0),
                        yEnd: .value("km/h", spd)
                    )
                    .foregroundStyle(.orange.opacity(0.2))

                    LineMark(
                        x: .value("km", km),
                        y: .value("km/h", spd)
                    )
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                .chartYScale(domain: 0...(maxSpeed * 1.1))
                .chartXAxisLabel("km")
                .chartYAxisLabel("km/h")
                .frame(height: 200)
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        )
    }

    // MARK: - Heart Rate Chart (with elevation overlay like Strava)

    private var heartRateChart: some View {
        let profile = track.heartRateProfile
        guard profile.count > 2 else { return AnyView(EmptyView()) }

        let sampled = sampleArray(profile, maxPoints: 300)
        let hrValues = sampled.map(\.hr)
        let minHR = Double(hrValues.min() ?? 60)
        let maxHR = Double(hrValues.max() ?? 180)
        let hrMargin = max((maxHR - minHR) * 0.1, 5)

        // Elevation data for background overlay (normalized to HR Y-axis)
        let eleProfile = sampleArray(track.elevationProfile, maxPoints: 300)
        let eleMin = eleProfile.map(\.elevation).min() ?? 0
        let eleMax = eleProfile.map(\.elevation).max() ?? 1
        let eleRange = max(eleMax - eleMin, 1)

        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
                Text("Frecuencia cardíaca")
                    .font(.headline)

                Chart {
                    // Elevation background (normalized to HR scale)
                    ForEach(eleProfile.indices, id: \.self) { (i: Int) in
                        let km = eleProfile[i].distance / 1000
                        let normalized = (eleProfile[i].elevation - eleMin) / eleRange
                        let mappedEle = (minHR - hrMargin) + normalized * (maxHR + hrMargin - (minHR - hrMargin)) * 0.6

                        AreaMark(
                            x: .value("km", km),
                            yStart: .value("base", minHR - hrMargin),
                            yEnd: .value("ele", mappedEle)
                        )
                        .foregroundStyle(.gray.opacity(0.15))
                    }

                    // HR area + line
                    ForEach(sampled.indices, id: \.self) { (i: Int) in
                        let km = sampled[i].distance / 1000
                        let hr = Double(sampled[i].hr)

                        AreaMark(
                            x: .value("km", km),
                            yStart: .value("base", minHR - hrMargin),
                            yEnd: .value("bpm", hr)
                        )
                        .foregroundStyle(.red.opacity(0.2))

                        LineMark(
                            x: .value("km", km),
                            y: .value("bpm", hr)
                        )
                        .foregroundStyle(.red)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }
                .chartYScale(domain: (minHR - hrMargin)...(maxHR + hrMargin))
                .chartXAxisLabel("km")
                .chartYAxisLabel("bpm")
                .frame(height: 200)
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        )
    }

    // MARK: - Sensor Comparison

    private var sensorSection: some View {
        // Skip first 20 minutes of sensor data (thermal stabilization)
        let stabilizationTime: TimeInterval = 20 * 60
        let startTime = track.points.first?.timestamp ?? Date()
        let stabilized = track.points.filter {
            $0.timestamp.timeIntervalSince(startTime) >= stabilizationTime
        }

        // Forecast averages (from stabilized range, or all if no stabilized sensor data)
        let forecastTemps = stabilized.compactMap { $0.temperature }
        let forecastHum = stabilized.compactMap { $0.forecastHumidity }
        let forecastPres = stabilized.compactMap { $0.forecastPressure }

        // Measured averages (from stabilized range only)
        let measuredTemps = stabilized.compactMap { $0.measuredTemperature }
        let measuredHum = stabilized.compactMap { $0.humidity }
        let measuredPres = stabilized.compactMap { $0.pressure }

        func avg(_ values: [Double]) -> Double? {
            values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }

        let avgForecastT = avg(forecastTemps)
        let avgMeasuredT = avg(measuredTemps)
        let avgForecastH = avg(forecastHum)
        let avgMeasuredH = avg(measuredHum)
        let avgForecastP = avg(forecastPres)
        let avgMeasuredP = avg(measuredPres)

        let skippedMinutes = Int(stabilizationTime / 60)

        return VStack(alignment: .leading, spacing: 8) {
            Text("Datos ambientales")
                .font(.headline)
            if !measuredTemps.isEmpty {
                Text("Primeros \(skippedMinutes) min excluidos (estabilización)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                Text("").frame(width: 80, alignment: .leading)
                Text("Forecast").frame(width: 75, alignment: .trailing)
                Text("Medido").frame(width: 75, alignment: .trailing)
                Text("Diff").frame(width: 60, alignment: .trailing)
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)

            if let fc = avgForecastT, let ms = avgMeasuredT {
                comparisonRow("Temp °C",
                              String(format: "%.1f", fc),
                              String(format: "%.1f", ms),
                              diff: ms - fc)
            }
            if let fh = avgForecastH, let mh = avgMeasuredH {
                comparisonRow("Humedad %",
                              String(format: "%.0f", fh),
                              String(format: "%.0f", mh),
                              diff: mh - fh)
            } else if let mh = avgMeasuredH {
                comparisonRow("Humedad %", "--", String(format: "%.0f", mh), diff: nil)
            }
            if let fp = avgForecastP, let mp = avgMeasuredP {
                comparisonRow("Presión hPa",
                              String(format: "%.1f", fp),
                              String(format: "%.1f", mp),
                              diff: mp - fp)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func comparisonRow(_ label: String, _ forecast: String, _ measured: String, diff: Double?) -> some View {
        HStack(spacing: 0) {
            Text(label).frame(width: 80, alignment: .leading)
            Text(forecast).frame(width: 75, alignment: .trailing)
                .foregroundStyle(forecast == "--" ? .secondary : .primary)
            Text(measured).frame(width: 75, alignment: .trailing)
            if let diff {
                Text(String(format: "%+.1f", diff))
                    .frame(width: 60, alignment: .trailing)
                    .foregroundStyle(abs(diff) < 1 ? .green : abs(diff) < 3 ? .orange : .red)
            } else {
                Text("").frame(width: 60)
            }
        }
        .font(.system(.caption, design: .monospaced))
    }

    // MARK: - Helpers

    private func sampleArray<T>(_ array: [T], maxPoints: Int) -> [T] {
        guard array.count > maxPoints else { return array }
        let step = Double(array.count) / Double(maxPoints)
        return (0..<maxPoints).map { array[Int(Double($0) * step)] }
    }

    private func paceColor(_ normalized: Double) -> Color {
        if normalized > 0.7 { return .green }
        if normalized > 0.4 { return .yellow }
        return .orange
    }

    // MARK: - Formatters

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = Locale(identifier: "es_ES")
        return f.string(from: date)
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.2f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%02d:%02d", m, sec)
    }

    private func formatSpeed(_ mps: Double) -> String {
        String(format: "%.1f km/h", mps * 3.6)
    }

    private func formatElevation(_ meters: Double?) -> String {
        guard let m = meters else { return "--" }
        return String(format: "%.0f m", m)
    }

    private func formatElevation(_ meters: Double) -> String {
        String(format: "%.0f m", meters)
    }

    private func formatPace(_ secondsPerKm: TimeInterval) -> String {
        guard secondsPerKm > 0, secondsPerKm < 3600 else { return "--:--" }
        let mins = Int(secondsPerKm) / 60
        let secs = Int(secondsPerKm) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    // MARK: - Reverse Geocoding

    /// Sample points along the track and resolve municipality names
    private func resolveLocalities() async {
        let points = track.points
        guard !points.isEmpty else { return }

        // Sample: start, every ~2km, end
        let cumDist = track.cumulativeDistances
        var sampleIndices = [0]
        var lastSampledDist = 0.0
        for i in 1..<points.count {
            if cumDist[i] - lastSampledDist >= 2000 {
                sampleIndices.append(i)
                lastSampledDist = cumDist[i]
            }
        }
        if sampleIndices.last != points.count - 1 {
            sampleIndices.append(points.count - 1)
        }

        var seen = Set<String>()
        var ordered: [String] = []

        let geocoder = CLGeocoder()
        for idx in sampleIndices {
            let p = points[idx]
            let location = CLLocation(latitude: p.latitude, longitude: p.longitude)
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                if let name = placemarks.first?.locality, !seen.contains(name) {
                    seen.insert(name)
                    ordered.append(name)
                }
            } catch {
                continue
            }
        }

        localities = ordered
    }
}
