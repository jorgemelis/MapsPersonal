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
    var isLive: Bool = false  // individual LIVE tracking state
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
    private var channelTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var liveRefreshTask: Task<Void, Never>?

    /// Map trackerId -> petId for quick lookup from channel events
    private var trackerToPet: [String: String] = [:]

    private static let baseURL = "https://graph.tractive.com/4"
    private static let channelURL = "https://channel.tractive.com/3/channel"
    private static let clientId = "625e533dc3c3b41c28a669f0"

    // MARK: - Credentials from Secrets.plist

    static var credentials: (email: String, password: String)? {
        // First try Keychain (user-configured in Settings)
        if let email = TractiveCredentials.email,
           let password = TractiveCredentials.password,
           !email.isEmpty, !password.isEmpty {
            return (email, password)
        }
        // Fallback to Secrets.plist (developer)
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let email = dict["TractiveEmail"] as? String,
              let password = dict["TractivePassword"] as? String else {
            return nil
        }
        return (email, password)
    }

    /// Disconnect and clear state
    func disconnect() {
        channelTask?.cancel()
        refreshTask?.cancel()
        liveRefreshTask?.cancel()
        perPetLiveTask?.cancel()
        perPetLiveTask = nil
        token = nil
        pets.removeAll()
        isConnected = false
    }

    // MARK: - Public API

    /// Connect: authenticate + discover all pets + fetch positions + start channel
    func connect() async {
        guard let creds = Self.credentials else {
            lastError = "Tractive credentials not found (check Settings or Secrets.plist)"
            print("🐾 Tractive: no credentials found in Keychain or Secrets.plist")
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
                trackerToPet[pet.trackerId] = pet.id
                do {
                    let pos = try await fetchPosition(trackerId: pet.trackerId, token: token!)
                    pet.position = pos
                    print("🐾 \(pet.name): pos=\(pos.coordinate.latitude),\(pos.coordinate.longitude)")
                } catch {
                    print("🐾 \(pet.name): fetchPosition FAILED: \(error)")
                }
                do {
                    let hw = try await fetchHardware(trackerId: pet.trackerId, token: token!)
                    pet.batteryLevel = hw.batteryLevel
                    pet.isCharging = hw.isCharging
                } catch {
                    print("🐾 \(pet.name): fetchHardware FAILED: \(error)")
                }
                discovered.append(pet)
            }

            pets = discovered
            isConnected = !pets.isEmpty
            lastError = nil
            print("🐾 Tractive: connected, \(pets.count) pets, isConnected=\(isConnected)")
            lastPositionUpdate = Date()

            // Start listening to the event channel
            startChannel()

            // Wake trackers to get a fresh position (like the official app does)
            await requestFreshPositions()
        } catch {
            lastError = error.localizedDescription
            isConnected = false
            print("🐾 Tractive: connect FAILED: \(error)")
        }
    }

    /// Toggle visibility of a pet
    func togglePet(_ petId: String) {
        if let idx = pets.firstIndex(where: { $0.id == petId }) {
            pets[idx].isVisible.toggle()
            lastPositionUpdate = Date()
        }
    }

    /// Start auto-refresh as fallback (every 60s for position, every 5min for battery)
    func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            var batteryCounter = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await refreshPositions()
                batteryCounter += 1
                if batteryCounter >= 5 {
                    await refreshBatteries()
                    batteryCounter = 0
                }
            }
        }
    }

    /// Stop auto-refresh
    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Event Channel (real-time updates)

    /// Start listening to Tractive's streaming event channel
    private func startChannel() {
        channelTask?.cancel()
        channelTask = Task {
            var retryDelay: TimeInterval = 1
            while !Task.isCancelled {
                do {
                    try await listenChannel()
                    // If listenChannel returns normally, reconnect
                    retryDelay = 1
                } catch is CancellationError {
                    return
                } catch {
                    print("🐾 Channel error: \(error), retrying in \(Int(retryDelay))s")
                }
                try? await Task.sleep(for: .seconds(retryDelay))
                retryDelay = min(retryDelay * 2, 30)
            }
        }
    }

    /// Open a streaming POST to the channel endpoint and process events
    private func listenChannel() async throws {
        guard let token else { throw TractiveError.notAuthenticated }

        try await refreshTokenIfNeeded()

        let url = URL(string: Self.channelURL)!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(Self.clientId, forHTTPHeaderField: "x-tractive-client")
        req.setValue(token.userId, forHTTPHeaderField: "x-tractive-user")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 90 // Keep-alive comes every ~30s

        print("🐾 Channel: connecting...")

        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw TractiveError.invalidResponse
        }
        if http.statusCode == 401 {
            // Token expired, force re-auth
            if let creds = Self.credentials {
                self.token = try await authenticate(email: creds.email, password: creds.password)
            }
            throw TractiveError.authFailed
        }
        guard (200..<300).contains(http.statusCode) else {
            print("🐾 Channel: HTTP \(http.statusCode)")
            throw TractiveError.httpError(http.statusCode)
        }

        print("🐾 Channel: connected, listening for events...")

        for try await line in bytes.lines {
            try Task.checkCancellation()

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == "keep-alive" { continue }

            guard let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            await handleChannelEvent(json)
        }

        print("🐾 Channel: stream ended")
    }

    /// Process a single event from the channel
    private func handleChannelEvent(_ event: [String: Any]) async {
        // The channel sends different message types
        let msgType = event["message"] as? String

        // Position update
        if let latlong = event["latlong"] as? [Double], latlong.count >= 2,
           let time = event["time"] as? TimeInterval {
            let trackerId = event["tracker_id"] as? String ?? event["_id"] as? String ?? ""
            let pos = TractivePosition(
                coordinate: CLLocationCoordinate2D(latitude: latlong[0], longitude: latlong[1]),
                altitude: event["altitude"] as? Double,
                speed: event["speed"] as? Double,
                accuracy: event["pos_uncertainty"] as? Double,
                timestamp: Date(timeIntervalSince1970: time)
            )

            if let petId = trackerToPet[trackerId],
               let idx = pets.firstIndex(where: { $0.id == petId }) {
                pets[idx].position = pos
                print("🐾 Channel: \(pets[idx].name) moved to \(pos.coordinate.latitude),\(pos.coordinate.longitude)")

                // Accumulate trail in hike mode
                if isLiveTracking {
                    var trail = petTrails[petId] ?? []
                    if let last = trail.last {
                        let dist = CLLocation(latitude: last.latitude, longitude: last.longitude)
                            .distance(from: CLLocation(latitude: pos.coordinate.latitude, longitude: pos.coordinate.longitude))
                        if dist > 3 {
                            trail.append(pos.coordinate)
                            petTrails[petId] = trail
                        }
                    } else {
                        petTrails[petId] = [pos.coordinate]
                    }
                }

                lastPositionUpdate = Date()
            } else {
                print("🐾 Channel: position for unknown tracker \(trackerId)")
            }
            return
        }

        // Battery / hardware update
        if let batteryLevel = event["battery_level"] as? Int {
            let trackerId = event["tracker_id"] as? String ?? event["_id"] as? String ?? ""
            if let petId = trackerToPet[trackerId],
               let idx = pets.firstIndex(where: { $0.id == petId }) {
                pets[idx].batteryLevel = batteryLevel
                pets[idx].isCharging = (event["charging_state"] as? String) == "CHARGING"
                print("🐾 Channel: \(pets[idx].name) battery=\(batteryLevel)%")
                lastPositionUpdate = Date()
            }
            return
        }

        // Log other event types for debugging
        if let msgType {
            print("🐾 Channel event: \(msgType)")
        }
    }

    // MARK: - Per-Pet LIVE Tracking

    /// Toggle LIVE tracking for an individual pet
    func toggleLiveTracking(_ petId: String) async {
        guard let token else { return }
        guard let idx = pets.firstIndex(where: { $0.id == petId }) else { return }

        let pet = pets[idx]
        let newState = !pet.isLive

        do {
            try await refreshTokenIfNeeded()
            let command = newState ? "on" : "off"
            _ = try await request(path: "/tracker/\(pet.trackerId)/command/live_tracking/\(command)", token: token, method: "POST")
            pets[idx].isLive = newState
            print("🐾 LIVE \(command.uppercased()) for \(pet.name)")

            if newState {
                // Start keep-alive for this pet if no global hike mode
                startPerPetLiveKeepAlive()
            } else {
                // Stop keep-alive if no pets are live
                if !pets.contains(where: { $0.isLive }) {
                    perPetLiveTask?.cancel()
                    perPetLiveTask = nil
                }
            }
        } catch {
            print("🐾 LIVE toggle failed for \(pet.name): \(error)")
        }

        lastPositionUpdate = Date()
    }

    private var perPetLiveTask: Task<Void, Never>?

    /// Keep-alive for individually activated LIVE pets
    private func startPerPetLiveKeepAlive() {
        guard perPetLiveTask == nil else { return }
        perPetLiveTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                guard let token = self.token else { continue }
                for pet in pets where pet.isLive {
                    _ = try? await request(path: "/tracker/\(pet.trackerId)/command/live_tracking/on", token: token, method: "POST")
                }
            }
        }
    }

    // MARK: - Wake Tracker (request fresh position)

    /// Send live_tracking/on to wake trackers, wait for fresh position, then turn off.
    /// This mimics what the official Tractive app does on launch.
    func requestFreshPositions() async {
        guard let token else { return }

        for pet in pets {
            do {
                try await refreshTokenIfNeeded()
                print("🐾 Waking tracker for \(pet.name)...")
                _ = try? await request(path: "/tracker/\(pet.trackerId)/command/live_tracking/on", token: token, method: "POST")
            } catch {
                print("🐾 Wake failed for \(pet.name): \(error)")
            }
        }

        // Wait for tracker to wake and send a position update via channel
        try? await Task.sleep(for: .seconds(15))

        // Fetch fresh positions explicitly in case channel didn't deliver
        await refreshPositions()

        // Turn off LIVE tracking to save tracker battery (unless hike mode is active)
        if !isLiveTracking {
            for pet in pets {
                _ = try? await request(path: "/tracker/\(pet.trackerId)/command/live_tracking/off", token: token, method: "POST")
            }
            print("🐾 Trackers back to normal mode")
        }
    }

    // MARK: - Hike Mode (LIVE tracking)

    /// Start hike mode: enable LIVE on visible pet trackers
    func startHikeMode() async {
        guard let token else { return }

        // Clear old trails
        petTrails.removeAll()

        do {
            try await refreshTokenIfNeeded()
        } catch { return }

        // Enable LIVE tracking on visible pets' trackers
        for pet in visiblePets {
            print("🐾 Enabling LIVE on \(pet.name) (\(pet.trackerId))")
            do {
                let liveData = try await request(path: "/tracker/\(pet.trackerId)/command/live_tracking/on", token: token, method: "POST")
                if let raw = String(data: liveData, encoding: .utf8) {
                    print("🐾 LIVE ON response: \(raw.prefix(300))")
                }
            } catch {
                print("🐾 LIVE ON FAILED for \(pet.name): \(error)")
            }
            // Seed trail with current position
            if let pos = pet.position {
                petTrails[pet.id] = [pos.coordinate]
            }
        }

        isLiveTracking = true
        print("🐾 HIKE MODE ON")

        // Keep LIVE active by re-sending command every 2 minutes
        liveRefreshTask?.cancel()
        liveRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                guard let token = self.token else { continue }
                for pet in visiblePets {
                    _ = try? await request(path: "/tracker/\(pet.trackerId)/command/live_tracking/on", token: token, method: "POST")
                    print("🐾 Re-sent LIVE ON for \(pet.name)")
                }
            }
        }
    }

    /// Stop hike mode: disable LIVE tracking
    func stopHikeMode() async {
        guard let token else { return }

        liveRefreshTask?.cancel()
        liveRefreshTask = nil

        // Disable LIVE on all trackers
        for pet in pets {
            print("🐾 Disabling LIVE on \(pet.name)")
            _ = try? await request(path: "/tracker/\(pet.trackerId)/command/live_tracking/off", token: token, method: "POST")
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

    // MARK: - Fallback: refresh positions via REST (used by auto-refresh)

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
            do {
                let pos = try await fetchPosition(trackerId: pets[i].trackerId, token: token)
                pets[i].position = pos
            } catch {
                // Silently continue on refresh failures
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

    private func request(path: String, token: TractiveToken, method: String = "GET") async throws -> Data {
        let url = URL(string: "\(Self.baseURL)\(path)")!
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(Self.clientId, forHTTPHeaderField: "x-tractive-client")
        req.setValue(token.userId, forHTTPHeaderField: "x-tractive-user")
        if method == "POST" {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

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
