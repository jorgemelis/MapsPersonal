import SwiftUI
import CoreLocation

// MARK: - Track Manager

struct TrackManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tracks: [GPXTrack] = []
    @State private var fileURLs: [String: URL] = [:]  // track name -> file URL
    @State private var isLoading = true
    @State private var shareURL: URL?
    @State private var uploadedFiles: Set<String> = []
    @State private var uploadingFile: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Cargando tracks...")
                } else if tracks.isEmpty {
                    ContentUnavailableView("Sin tracks", systemImage: "point.topleft.down.to.point.bottomright.curvepath", description: Text("Los tracks grabados aparecerán aquí"))
                } else {
                    trackList
                }
            }
            .navigationTitle("Tracks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
        .onAppear { loadTracks() }
        .sheet(isPresented: Binding(
            get: { shareURL != nil },
            set: { if !$0 { shareURL = nil } }
        )) {
            if let url = shareURL {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - Track List

    private var trackList: some View {
        List {
            ForEach(tracks) { track in
                NavigationLink(destination: TrackAnalysisView(track: track)) {
                    TrackRowView(
                        track: track,
                        fileURL: fileURLs[track.name],
                        isUploading: uploadingFile == track.name,
                        isUploaded: uploadedFiles.contains(track.name),
                        onUpload: { uploadToICloud(track) },
                        onShare: {
                            if let url = fileURLs[track.name] { shareURL = url }
                        }
                    )
                }
            }
            .onDelete(perform: deleteTracks)
        }
    }

    // MARK: - Loading

    private func loadTracks() {
        isLoading = true
        Task {
            let files = TrackRecorder.savedFiles()
            var parsed: [GPXTrack] = []
            var urls: [String: URL] = [:]

            for file in files {
                if let track = GPXParser.parse(url: file) {
                    parsed.append(track)
                    urls[track.name] = file
                }
            }

            parsed.sort { $0.startDate > $1.startDate }
            tracks = parsed
            fileURLs = urls
            isLoading = false
        }
    }

    private func deleteTracks(at offsets: IndexSet) {
        for index in offsets {
            let track = tracks[index]
            if let url = fileURLs[track.name] {
                TrackRecorder.deleteFile(at: url)
            }
        }
        tracks.remove(atOffsets: offsets)
    }

    private func uploadToICloud(_ track: GPXTrack) {
        guard let url = fileURLs[track.name] else { return }
        uploadingFile = track.name
        DispatchQueue.global(qos: .userInitiated).async {
            let success = TrackRecorder.copyToICloud(url)
            DispatchQueue.main.async {
                uploadingFile = nil
                if success {
                    uploadedFiles.insert(track.name)
                }
            }
        }
    }
}

// MARK: - Track Row

private struct TrackRowView: View {
    let track: GPXTrack
    let fileURL: URL?
    let isUploading: Bool
    let isUploaded: Bool
    let onUpload: () -> Void
    let onShare: () -> Void
    @State private var locality: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Date + locality + indicators
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(formattedDate(track.startDate))
                        .font(.subheadline.weight(.medium))
                    if let loc = locality {
                        Text(loc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if track.hasHeartRate {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
                if track.hasSensorData {
                    Image(systemName: "sensor.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }

            // Stats line
            HStack(spacing: 12) {
                Label(formatDistance(track.totalDistance), systemImage: "arrow.left.and.right")
                Label(formatElevation(track.elevationGain), systemImage: "arrow.up.right")
                Label(formatDuration(track.movingTime), systemImage: "figure.walk")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Actions
            HStack {
                Spacer()

                Button(action: onUpload) {
                    if isUploading {
                        ProgressView().controlSize(.small)
                    } else if isUploaded {
                        Image(systemName: "checkmark.icloud.fill")
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "icloud.and.arrow.up")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isUploaded || isUploading)

                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
        .task {
            guard locality == nil, let first = track.points.first else { return }
            let location = CLLocation(latitude: first.latitude, longitude: first.longitude)
            if let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first {
                locality = placemark.locality
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = Locale(identifier: "es_ES")
        return f.string(from: date)
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        if h > 0 { return String(format: "%dh%02dm", h, m) }
        return String(format: "%dm", m)
    }

    private func formatElevation(_ meters: Double) -> String {
        String(format: "+%.0fm", meters)
    }
}
