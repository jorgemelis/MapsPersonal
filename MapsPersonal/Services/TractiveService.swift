import Foundation
import CoreLocation

// MARK: - Tractive API Models

struct TractiveToken {
    let accessToken: String
    let userId: String
    let expiresAt: Date
}

struct TractiveTracker: Identifiable {
    let id: String
    let modelNumber: String?
}

struct TractivePet: Identifiable {
    let id: String
    let name: String
    let emoji: String   // 🐕 or 🐱
    let trackerId: String
    var position: TractivePosition?
    var batteryLevel: Int?
    var isCharging: Bool = false
    var isVisible: Bool = true
}

struct TractivePosition {
    let coordinate: CLLocationCoordinate2D
    let altitude: Double?
    let speed: Double?
    let accuracy: Double?
    let timestamp: Date
}

struct TractiveHardware {
    let batteryLevel: Int
    let isCharging: Bool
}

// MARK: - Tractive Service

@MainActor
@Observable
class TractiveService {
    var pets: [TractivePet] = []
    var isConnected = false
    var lastError: String?

    /// Live tracking state (activated during hike recording)
    var isLiveTracking = false

    /// Accumulated pet trail during hike recording (petId -> coordinates)
    var petTrails: [String: [CLLocationCoordinate2D]] = [:]

    /// Visible pets with position data (for map display)
    var visiblePets: [TractivePet] {
        pets.filter { $0.isVisible && $0.position != nil }
    }

    /// Timestamp that changes when any pet position updates (triggers SwiftUI refresh)
    var lastPositionUpdate: Date?

    private var token: TractiveToken?
    private var refreshTask: Task<Void, Never>?
    private var liveRefreshTask: Task<Void, Never>?

    private static let baseURL = "https://graph.tractive.com/4"
    private static let clientId = "625e533dc3c3b41c28a669f0"

    // MARK: - Credentials from Secrets.plist

    private static let credentials: (email: String, password: String)? = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let email = dict["TractiveEmail"] as? String,
              let password = dict["TractivePassword"] as? String else {
            return nil
        }
        return (email, password)
    }()

    // MARK: - Public API

    /// Connect: authenticate + discover all pets + fetch positions
    func connect() async {
        guard let creds = Self.credentials else {
            lastError = "Tractive credentials not found in Secrets.plist"
            print("🐾 Tractive: no credentials found")
            return
        }

        do {
            print("🐾 Tractive: authenticating...")
            token = try await authenticate(email: creds.email, password: creds.password)
            print("🐾 Tractive: auth OK, user=\(token!.userId)")

            let rawPets = try await fetchPets()
            print("🐾 Tractive: found \(rawPets.count) pets: \(rawPets.map { $0.name })")

            // Build pet list with positions
            var discovered: [TractivePet] = []
            for raw in rawPets {
                var pet = raw
                if let pos = try? await fetchPosition(trackerId: pet.trackerId, token: token!) {
                    pet.position = pos
                    print("🐾 \(pet.name): pos=\(pos.coordinate.latitude),\(pos.coordinate.longitude)")
                }
                let hw = try? await fetchHardware(trackerId: pet.trackerId, token: token!)
                pet.batteryLevel = hw?.batteryLevel
                pet.isCharging = hw?.isCharging ?? false
                discovered.append(pet)
            }

            pets = discovered
            isConnected = !pets.isEmpty
            lastError = nil
            print("🐾 Tractive: connected, \(pets.count) pets, isConnected=\(isConnected)")
            lastPositionUpdate = Date()
        } catch {
            lastError = error.localizedDescription
            isConnected = false
        }
    }

    /// Toggle visibility of a pet
    func togglePet(_ petId: String) {
        if let idx = pets.firstIndex(where: { $0.id == petId }) {
            pets[idx].isVisible.toggle()
            lastPositionUpdate = Date()
        }
    }

    /// Refresh all visible pet positions
    func refreshPositions() async {
        guard let token else { return }

        do {
            try await refreshTokenIfNeeded()
        } catch {
            lastError = error.localizedDescription
            return
        }

        for i in pets.indices where pets[i].isVisible {
            if let pos = try? await fetchPosition(trackerId: pets[i].trackerId, token: token) {
                pets[i].position = pos
            }
        }
        lastPositionUpdate = Date()
    }

    /// Refresh battery for all pets
    func refreshBatteries() async {
        guard let token else { return }

        do {
            try await refreshTokenIfNeeded()
        } catch { return }

        for i in pets.indices {
            if let hw = try? await fetchHardware(trackerId: pets[i].trackerId, token: token) {
                pets[i].batteryLevel = hw.batteryLevel
                pets[i].isCharging = hw.isCharging
            }
        }
    }

    /// Start auto-refresh (every 30s for position, every 5min for battery)
    func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            var batteryCounter = 0
            while !Task.isCancelled {
                await refreshPositions()
                batteryCounter += 1
                if batteryCounter >= 10 {
                    await refreshBatteries()
                    batteryCounter = 0
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    /// Stop auto-refresh
    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Hike Mode (LIVE tracking + trail recording)

    /// Start hike mode: enable LIVE on visible pet trackers + fast refresh (5s) + accumulate trail
    func startHikeMode() async {
        guard let token else { return }

        // Clear old trails
        petTrails.removeAll()

        // Enable LIVE tracking on visible pets' trackers
        do {
            try await refreshTokenIfNeeded()
        } catch { return }

        for pet in visiblePets {
            _ = try? await request(path: "/tracker/\(pet.trackerId)/command/live_tracking/on", token: token)
            // Seed trail with current position
            if let pos = pet.position {
                petTrails[pet.id] = [pos.coordinate]
            }
        }

        isLiveTracking = true

        // Fast refresh loop: every 5s during hike
        liveRefreshTask?.cancel()
        liveRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                await refreshPositions()

                // Append new positions to trails
                for pet in visiblePets {
                    guard let pos = pet.position else { continue }
                    var trail = petTrails[pet.id] ?? []
                    // Only add if moved (avoid duplicates)
                    if let last = trail.last {
                        let dist = CLLocation(latitude: last.latitude, longitude: last.longitude)
                            .distance(from: CLLocation(latitude: pos.coordinate.latitude, longitude: pos.coordinate.longitude))
                        if dist > 3 { // at least 3m movement
                            trail.append(pos.coordinate)
                            petTrails[pet.id] = trail
                        }
                    } else {
                        petTrails[pet.id] = [pos.coordinate]
                    }
                }
                lastPositionUpdate = Date()
            }
        }
    }

    /// Stop hike mode: disable LIVE tracking + return to normal refresh
    func stopHikeMode() async {
        guard let token else { return }

        liveRefreshTask?.cancel()
        liveRefreshTask = nil

        // Disable LIVE on all trackers
        for pet in pets {
            _ = try? await request(path: "/tracker/\(pet.trackerId)/command/live_tracking/off", token: token)
        }

        isLiveTracking = false
    }

    /// Get trail coordinates for a pet (for drawing polyline)
    func trail(for petId: String) -> [CLLocationCoordinate2D] {
        petTrails[petId] ?? []
    }

    /// Fetch position history for a specific tracker
    func fetchHistory(trackerId: String, from: Date, to: Date) async -> [TractivePosition] {
        guard let token else { return [] }

        do {
            try await refreshTokenIfNeeded()
            return try await fetchPositions(trackerId: trackerId, token: token, from: from, to: to)
        } catch {
            lastError = "History: \(error.localizedDescription)"
            return []
        }
    }

    // MARK: - Authentication

    private func authenticate(email: String, password: String) async throws -> TractiveToken {
        let url = URL(string: "\(Self.baseURL)/auth/token")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.clientId, forHTTPHeaderField: "x-tractive-client")

        let body: [String: String] = [
            "platform_email": email,
            "platform_token": password,
            "grant_type": "tractive"
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        try checkHTTPResponse(response)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let accessToken = json["access_token"] as? String,
              let userId = json["user_id"] as? String,
              let expiresAt = json["expires_at"] as? TimeInterval else {
            throw TractiveError.authFailed
        }

        return TractiveToken(
            accessToken: accessToken,
            userId: userId,
            expiresAt: Date(timeIntervalSince1970: expiresAt)
        )
    }

    private func refreshTokenIfNeeded() async throws {
        guard let token else { throw TractiveError.notAuthenticated }
        if token.expiresAt.timeIntervalSinceNow < 300 {
            guard let creds = Self.credentials else { throw TractiveError.notAuthenticated }
            self.token = try await authenticate(email: creds.email, password: creds.password)
        }
    }

    // MARK: - API Calls

    private func fetchPets() async throws -> [TractivePet] {
        guard let token else { throw TractiveError.notAuthenticated }
        let data = try await request(path: "/user/\(token.userId)/trackable_objects", token: token)
        guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            print("🐾 fetchPets: failed to parse list")
            return []
        }

        var results: [TractivePet] = []
        for item in list {
            guard let petId = item["_id"] as? String else { continue }

            // Always fetch full pet object (list only has stubs without device_id)
            guard let detailData = try? await request(path: "/trackable_object/\(petId)", token: token),
                  let full = try? JSONSerialization.jsonObject(with: detailData) as? [String: Any],
                  let deviceId = full["device_id"] as? String else {
                print("🐾 fetchPets: skipping \(petId), no device_id")
                continue
            }

            var name = "Pet"
            var petType = "DOG"
            if let details = full["details"] as? [String: Any] {
                name = details["name"] as? String ?? "Pet"
                petType = details["pet_type"] as? String ?? "DOG"
            }

            let emoji = petType == "CAT" ? "🐱" : "🐕"
            results.append(TractivePet(id: petId, name: name, emoji: emoji, trackerId: deviceId))
            print("🐾 fetchPets: \(name) (\(emoji)) tracker=\(deviceId)")
        }

        return results
    }

    private func fetchPosition(trackerId: String, token: TractiveToken) async throws -> TractivePosition {
        let data = try await request(path: "/device_pos_report/\(trackerId)", token: token)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        guard let latlong = json["latlong"] as? [Double], latlong.count >= 2,
              let time = json["time"] as? TimeInterval else {
            throw TractiveError.invalidResponse
        }

        return TractivePosition(
            coordinate: CLLocationCoordinate2D(latitude: latlong[0], longitude: latlong[1]),
            altitude: json["altitude"] as? Double,
            speed: json["speed"] as? Double,
            accuracy: json["pos_uncertainty"] as? Double,
            timestamp: Date(timeIntervalSince1970: time)
        )
    }

    private func fetchHardware(trackerId: String, token: TractiveToken) async throws -> TractiveHardware {
        let data = try await request(path: "/device_hw_report/\(trackerId)/", token: token)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return TractiveHardware(batteryLevel: 0, isCharging: false)
        }

        return TractiveHardware(
            batteryLevel: json["battery_level"] as? Int ?? 0,
            isCharging: (json["charging_state"] as? String) == "CHARGING"
        )
    }

    private func fetchPositions(trackerId: String, token: TractiveToken, from: Date, to: Date) async throws -> [TractivePosition] {
        let fromTs = Int(from.timeIntervalSince1970)
        let toTs = Int(to.timeIntervalSince1970)
        let data = try await request(
            path: "/tracker/\(trackerId)/positions?time_from=\(fromTs)&time_to=\(toTs)&format=json_segments",
            token: token
        )

        guard let segments = try JSONSerialization.jsonObject(with: data) as? [[[String: Any]]] else {
            return []
        }

        return segments.flatMap { segment in
            segment.compactMap { json -> TractivePosition? in
                guard let latlong = json["latlong"] as? [Double], latlong.count >= 2,
                      let time = json["time"] as? TimeInterval else { return nil }
                return TractivePosition(
                    coordinate: CLLocationCoordinate2D(latitude: latlong[0], longitude: latlong[1]),
                    altitude: json["altitude"] as? Double,
                    speed: json["speed"] as? Double,
                    accuracy: json["pos_uncertainty"] as? Double,
                    timestamp: Date(timeIntervalSince1970: time)
                )
            }
        }
    }

    // MARK: - HTTP Helper

    private func request(path: String, token: TractiveToken) async throws -> Data {
        let url = URL(string: "\(Self.baseURL)\(path)")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(Self.clientId, forHTTPHeaderField: "x-tractive-client")
        req.setValue(token.userId, forHTTPHeaderField: "x-tractive-user")

        let (data, response) = try await URLSession.shared.data(for: req)
        try checkHTTPResponse(response)
        return data
    }

    private func checkHTTPResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300: return
        case 401: throw TractiveError.authFailed
        case 429: throw TractiveError.rateLimited
        default: throw TractiveError.httpError(http.statusCode)
        }
    }
}

// MARK: - Errors

enum TractiveError: LocalizedError {
    case authFailed
    case notAuthenticated
    case invalidResponse
    case rateLimited
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .authFailed: return "Tractive auth failed"
        case .notAuthenticated: return "Not authenticated"
        case .invalidResponse: return "Invalid API response"
        case .rateLimited: return "Rate limited (429)"
        case .httpError(let code): return "HTTP \(code)"
        }
    }
}
