import Foundation

// MARK: - Offline Maps Manager

/// Scans Documents directory for .mbtiles files and manages tile servers for each.
/// Users can add/remove .mbtiles files via Finder (iTunes File Sharing).
@Observable
class OfflineMapsManager {
    var availableMaps: [OfflineMapInfo] = []
    private var servers: [String: LocalTileServer] = [:]
    private var nextPort: UInt16 = 8770

    struct OfflineMapInfo: Identifiable {
        let id: String // filename without extension
        let name: String
        let path: String
        let fileSize: Int64
        var urlTemplate: String?
        var isActive: Bool = false
    }

    /// Scan Documents and iCloud Maps directory for .mbtiles files
    func scan() {
        var maps: [OfflineMapInfo] = []

        // Local Documents (via Finder/File Sharing)
        if let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            maps += scanDirectory(docsURL.path)
        }

        // iCloud Maps (transferred from Control Center on Mac)
        if let container = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.jorge.mapspersonal2026") {
            let mapsDir = container.appendingPathComponent("Documents/Maps")
            let fm = FileManager.default
            if !fm.fileExists(atPath: mapsDir.path) {
                try? fm.createDirectory(at: mapsDir, withIntermediateDirectories: true)
            }
            maps += scanDirectory(mapsDir.path)
        }

        availableMaps = maps
    }

    /// Start serving a specific map
    func activate(_ mapId: String) -> String? {
        guard let index = availableMaps.firstIndex(where: { $0.id == mapId }) else { return nil }

        if let existing = servers[mapId] {
            return existing.urlTemplate
        }

        // If the file is in iCloud, copy to local for fast access
        let path = ensureLocal(availableMaps[index].path)

        let server = LocalTileServer(port: nextPort)
        nextPort += 1

        if server.start(mbtilesPath: path) {
            servers[mapId] = server
            availableMaps[index].urlTemplate = server.urlTemplate
            availableMaps[index].isActive = true
            return server.urlTemplate
        }
        return nil
    }

    /// Copy iCloud file to local Documents if needed, return local path
    private func ensureLocal(_ path: String) -> String {
        // If already in Documents, use as-is
        let docsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? ""
        if path.hasPrefix(docsPath) {
            return path
        }

        // iCloud file — copy to local Documents for fast tile serving
        let fm = FileManager.default
        let filename = (path as NSString).lastPathComponent
        let localPath = (docsPath as NSString).appendingPathComponent(filename)

        if !fm.fileExists(atPath: localPath) {
            // Trigger iCloud download if needed
            let url = URL(fileURLWithPath: path)
            try? fm.startDownloadingUbiquitousItem(at: url)

            // Copy to local
            try? fm.copyItem(atPath: path, toPath: localPath)
        }

        return fm.fileExists(atPath: localPath) ? localPath : path
    }

    /// Stop serving a specific map
    func deactivate(_ mapId: String) {
        servers.removeValue(forKey: mapId)
        if let index = availableMaps.firstIndex(where: { $0.id == mapId }) {
            availableMaps[index].urlTemplate = nil
            availableMaps[index].isActive = false
        }
    }

    private func scanDirectory(_ path: String) -> [OfflineMapInfo] {
        var results: [OfflineMapInfo] = []
        let fm = FileManager.default

        guard let files = try? fm.contentsOfDirectory(atPath: path) else { return [] }

        for file in files where file.hasSuffix(".mbtiles") {
            let fullPath = (path as NSString).appendingPathComponent(file)
            let name = (file as NSString).deletingPathExtension
            let id = name

            var fileSize: Int64 = 0
            if let attrs = try? fm.attributesOfItem(atPath: fullPath) {
                fileSize = attrs[.size] as? Int64 ?? 0
            }

            // Try to read the description from MBTiles metadata
            let displayName = readMBTilesName(path: fullPath) ?? name.replacingOccurrences(of: "_", with: " ").capitalized

            results.append(OfflineMapInfo(
                id: id,
                name: displayName,
                path: fullPath,
                fileSize: fileSize
            ))
        }

        return results
    }

    private func readMBTilesName(path: String) -> String? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let sql = "SELECT value FROM metadata WHERE name = 'name'"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let cString = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: cString)
    }
}

import SQLite3
