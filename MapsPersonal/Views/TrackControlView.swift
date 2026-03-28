import SwiftUI

// MARK: - Track Control Overlay

struct TrackControlView: View {
    let recorder: TrackRecorder
    let onStart: () -> Void
    let onStop: () -> Void
    let onSave: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        if recorder.isRecording {
            recordingView
        } else if recorder.currentTrack != nil {
            stoppedView
        } else {
            startButton
        }
    }

    private var startButton: some View {
        Button(action: onStart) {
            Image(systemName: "record.circle")
                .font(.title2)
                .foregroundStyle(.red)
                .padding(12)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    private var recordingView: some View {
        HStack(spacing: 16) {
            // Pulsing red dot
            Circle()
                .fill(.red)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(formattedDuration)
                    .font(.system(.body, design: .monospaced))
                Text(formattedDistance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Temperature (weather model forecast)
            if let temp = recorder.currentTemperature {
                HStack(spacing: 2) {
                    Image(systemName: "thermometer.medium")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text(String(format: "%.0f°", temp))
                        .font(.system(.caption, design: .monospaced))
                }
            }

            // Heart rate + zone
            if let hr = recorder.heartRateService.currentHeartRate {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text("\(hr)")
                        .font(.system(.body, design: .monospaced))
                    if let zi = recorder.currentZoneIndex {
                        Text("Z\(zi + 1)")
                            .font(.system(.caption, design: .monospaced, weight: .bold))
                            .foregroundStyle(zoneColor(zi))
                    }
                }
            }

            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var stoppedView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(recorder.pointCount) puntos")
                        .font(.body)
                    Text(formattedDistance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Guardar", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                Button("Descartar", action: onDiscard)
                    .buttonStyle(.bordered)
                    .tint(.red)
            }

            // HR zone distribution bar
            if totalZoneTime > 0 {
                zoneDistributionBar
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var totalZoneTime: TimeInterval {
        recorder.zoneTimeDistribution.reduce(0, +)
    }

    @ViewBuilder
    private var zoneDistributionBar: some View {
        let total = totalZoneTime
        VStack(spacing: 4) {
            // Stacked horizontal bar
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(0..<recorder.zoneTimeDistribution.count, id: \.self) { i in
                        let fraction = recorder.zoneTimeDistribution[i] / total
                        if fraction > 0.01 {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(zoneColor(i))
                                .frame(width: max(geo.size.width * fraction - 1, 2))
                                .overlay {
                                    if fraction > 0.08 {
                                        Text("Z\(i + 1)")
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                    }
                }
            }
            .frame(height: 16)

            // Zone legend with times
            HStack(spacing: 8) {
                ForEach(0..<recorder.zoneTimeDistribution.count, id: \.self) { i in
                    let secs = recorder.zoneTimeDistribution[i]
                    if secs > 0 {
                        HStack(spacing: 2) {
                            Circle()
                                .fill(zoneColor(i))
                                .frame(width: 6, height: 6)
                            Text("\(formatZoneTime(secs))")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func formatZoneTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins > 0 {
            return "\(mins)m"
        }
        return "\(secs)s"
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

    private var formattedDuration: String {
        let seconds = Int(recorder.duration)
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    private var formattedDistance: String {
        let dist = recorder.totalDistance
        if dist >= 1000 {
            return String(format: "%.2f km", dist / 1000)
        }
        return String(format: "%.0f m", dist)
    }
}
