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

            // Heart rate
            if let hr = recorder.heartRateService.currentHeartRate {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text("\(hr)")
                        .font(.system(.body, design: .monospaced))
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
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
