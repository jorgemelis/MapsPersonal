import Foundation
import SQLite3
import Network

// MARK: - Local Tile Server for MBTiles

/// Serves tiles from an MBTiles file via a local HTTP server.
/// MapLibre loads tiles from http://localhost:{port}/{z}/{x}/{y}.png
final class LocalTileServer: Sendable {
    let port: UInt16
    private let dbWrapper: DatabaseWrapper

    init(port: UInt16 = 8765) {
        self.port = port
        self.dbWrapper = DatabaseWrapper()
    }

    nonisolated var urlTemplate: String {
        "http://localhost:\(port)/{z}/{x}/{y}.png"
    }

    @MainActor
    func start(mbtilesPath: String) -> Bool {
        guard FileManager.default.fileExists(atPath: mbtilesPath) else {
            print("LocalTileServer: MBTiles file not found: \(mbtilesPath)")
            return false
        }

        guard dbWrapper.open(path: mbtilesPath) else {
            print("LocalTileServer: Failed to open MBTiles database")
            return false
        }

        let listener: NWListener
        do {
            listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            print("LocalTileServer: Failed to create listener: \(error)")
            return false
        }

        let queue = DispatchQueue(label: "tile-server-\(port)", qos: .userInitiated)
        let wrapper = self.dbWrapper

        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                guard let data, let request = String(data: data, encoding: .utf8) else {
                    connection.cancel()
                    return
                }

                let lines = request.split(separator: "\r\n")
                guard let firstLine = lines.first else { connection.cancel(); return }
                let parts = firstLine.split(separator: " ")
                guard parts.count >= 2 else { connection.cancel(); return }

                let path = String(parts[1])
                let tileData = Self.getTileForPath(path, db: wrapper)

                let response: Data
                if let tileData {
                    let header = "HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: \(tileData.count)\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
                    response = header.data(using: .utf8)! + tileData
                } else {
                    response = "HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n".data(using: .utf8)!
                }

                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }

        listener.start(queue: queue)
        return true
    }

    // MARK: - Static tile lookup (no self capture needed)

    private static func getTileForPath(_ path: String, db: DatabaseWrapper) -> Data? {
        let components = path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: ".png", with: "")
            .split(separator: "/")

        guard components.count == 3,
              let z = Int(components[0]),
              let x = Int(components[1]),
              let y = Int(components[2]) else {
            return nil
        }

        let tmsY = (1 << z) - 1 - y
        return db.getTile(z: z, x: x, y: tmsY)
    }
}

// MARK: - Thread-safe SQLite wrapper

final class DatabaseWrapper: Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var db: OpaquePointer?

    func open(path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK
    }

    func getTile(z: Int, x: Int, y: Int) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return nil }

        var stmt: OpaquePointer?
        let sql = "SELECT tile_data FROM tiles WHERE zoom_level = ? AND tile_column = ? AND tile_row = ?"

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(z))
        sqlite3_bind_int(stmt, 2, Int32(x))
        sqlite3_bind_int(stmt, 3, Int32(y))

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        let bytes = sqlite3_column_blob(stmt, 0)
        let length = sqlite3_column_bytes(stmt, 0)

        guard let bytes, length > 0 else { return nil }
        return Data(bytes: bytes, count: Int(length))
    }
}
