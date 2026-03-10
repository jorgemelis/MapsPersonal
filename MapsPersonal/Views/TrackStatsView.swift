import SwiftUI

// MARK: - Track Stats View (like Wikiloc)

struct TrackStatsView: View {
    let recorder: TrackRecorder

    var body: some View {
        let track = recorder.currentTrack

        VStack(spacing: 0) {
            // Header with recording indicator
            HStack {
                if recorder.isRecording {
                    Circle()
                        .fill(.red)
                        .frame(width: 10, height: 10)
                    Text("GRABANDO")
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                }
                Spacer()
                Text("\(recorder.pointCount) pts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Main stats grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 12) {
                // Distance
                StatCell(
                    icon: "arrow.left.and.right",
                    label: "Distancia",
                    value: formatDistance(track?.totalDistance ?? 0)
                )

                // Total time
                StatCell(
                    icon: "clock",
                    label: "Tiempo total",
                    value: formatDuration(track?.duration ?? 0)
                )

                // Moving time
                StatCell(
                    icon: "figure.walk",
                    label: "En movimiento",
                    value: formatDuration(track?.movingTime ?? 0)
                )

                // Stopped time
                StatCell(
                    icon: "pause.circle",
                    label: "Parado",
                    value: formatDuration(track?.stoppedTime ?? 0)
                )

                // Average speed
                StatCell(
                    icon: "speedometer",
                    label: "Vel. media",
                    value: formatSpeed(track?.averageMovingSpeed ?? 0)
                )

                // Current elevation
                StatCell(
                    icon: "mountain.2",
                    label: "Altitud",
                    value: formatElevation(track?.currentElevation)
                )

                // Elevation gain
                StatCell(
                    icon: "arrow.up.right",
                    label: "Desnivel +",
                    value: formatElevation(track?.elevationGain)
                )

                // Elevation loss
                StatCell(
                    icon: "arrow.down.right",
                    label: "Desnivel -",
                    value: formatElevation(track?.elevationLoss)
                )

                // Min elevation
                StatCell(
                    icon: "arrow.down",
                    label: "Alt. mín",
                    value: formatElevation(track?.minElevation)
                )

                // Max elevation
                StatCell(
                    icon: "arrow.up",
                    label: "Alt. máx",
                    value: formatElevation(track?.maxElevation)
                )
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Formatters

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
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, sec)
        }
        return String(format: "%02d:%02d", m, sec)
    }

    private func formatSpeed(_ mps: Double) -> String {
        let kmh = mps * 3.6
        return String(format: "%.1f km/h", kmh)
    }

    private func formatElevation(_ meters: Double?) -> String {
        guard let m = meters else { return "--" }
        return String(format: "%.0f m", m)
    }
}

// MARK: - Compact Stats (one-line with integrated stop button)

struct TrackStatsCompactView: View {
    let recorder: TrackRecorder
    var onStop: (() -> Void)? = nil
    var onSave: (() -> Void)? = nil
    var onDiscard: (() -> Void)? = nil

    @State private var showDiscardAlert = false

    var body: some View {
        let track = recorder.currentTrack

        HStack(spacing: 8) {
            if recorder.isRecording {
                // Recording: dot + stats + stop
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)

                Text(formatDuration(track?.duration ?? 0))
                Text(formatDistance(track?.totalDistance ?? 0))
                Text(formatElevation(track?.elevationGain))

                Spacer()

                Button {
                    onStop?()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(6)
                        .background(.red.opacity(0.15), in: Circle())
                }
            } else if recorder.currentTrack != nil {
                // Stopped: summary + save/discard
                Text("\(recorder.pointCount) pts")
                Text(formatDistance(track?.totalDistance ?? 0))
                Text(formatElevation(track?.elevationGain))

                Spacer()

                Button {
                    onSave?()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(6)
                        .background(.green.opacity(0.15), in: Circle())
                }

                Button {
                    showDiscardAlert = true
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(6)
                        .background(.red.opacity(0.15), in: Circle())
                }
            }
        }
        .font(.system(.caption, design: .monospaced))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .alert("Descartar track", isPresented: $showDiscardAlert) {
            Button("Descartar", role: .destructive) {
                onDiscard?()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("¿Seguro? Se perderá el track grabado.")
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1fkm", meters / 1000)
        }
        return String(format: "%.0fm", meters)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%02d:%02d", m, sec)
    }

    private func formatElevation(_ meters: Double?) -> String {
        guard let m = meters else { return "+--m" }
        return String(format: "+%.0fm", m)
    }
}

// MARK: - Stat Cell

struct StatCell: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(.body, design: .monospaced, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
