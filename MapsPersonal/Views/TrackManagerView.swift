import SwiftUI

// MARK: - Track Manager

struct TrackManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var files: [URL] = []
    @State private var shareURL: URL?
    @State private var uploadedFiles: Set<String> = []
    @State private var uploadingFile: String?

    var body: some View {
        NavigationStack {
            Group {
                if files.isEmpty {
                    ContentUnavailableView("Sin tracks", systemImage: "point.topleft.down.to.point.bottomright.curvepath", description: Text("Los tracks grabados aparecerán aquí"))
                } else {
                    List {
                        ForEach(files, id: \.absoluteString) { file in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.deletingPathExtension().lastPathComponent)
                                        .font(.body)
                                    Text(fileSize(file))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                // iCloud button
                                Button {
                                    uploadToICloud(file)
                                } label: {
                                    if uploadingFile == file.lastPathComponent {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else if uploadedFiles.contains(file.lastPathComponent) {
                                        Image(systemName: "checkmark.icloud.fill")
                                            .foregroundStyle(.green)
                                    } else {
                                        Image(systemName: "icloud.and.arrow.up")
                                    }
                                }
                                .buttonStyle(.borderless)
                                .disabled(uploadedFiles.contains(file.lastPathComponent) || uploadingFile != nil)

                                // Share button
                                Button {
                                    shareURL = file
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.body)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .onDelete(perform: deleteFiles)
                    }
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
        .onAppear { files = TrackRecorder.savedFiles() }
        .sheet(isPresented: Binding(
            get: { shareURL != nil },
            set: { if !$0 { shareURL = nil } }
        )) {
            if let url = shareURL {
                ShareSheet(items: [url])
            }
        }
    }

    private func uploadToICloud(_ file: URL) {
        uploadingFile = file.lastPathComponent
        DispatchQueue.global(qos: .userInitiated).async {
            let success = TrackRecorder.copyToICloud(file)
            DispatchQueue.main.async {
                uploadingFile = nil
                if success {
                    uploadedFiles.insert(file.lastPathComponent)
                }
            }
        }
    }

    private func deleteFiles(at offsets: IndexSet) {
        for index in offsets {
            TrackRecorder.deleteFile(at: files[index])
        }
        files.remove(atOffsets: offsets)
    }

    private func fileSize(_ url: URL) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int else { return "" }
        if size > 1024 * 1024 {
            return String(format: "%.1f MB", Double(size) / 1_048_576)
        }
        return String(format: "%.0f KB", Double(size) / 1024)
    }
}
