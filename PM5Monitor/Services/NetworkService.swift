import Foundation
import Combine
import SocketIO

// MARK: - Network Configuration
/*
 ============================================
 SERVER SETUP
 ============================================

 1. Start the server locally:
    cd Server && npm install && npm start

 2. For internet access, use ngrok:
    ngrok http 3000

 3. Update serverURL below with your URL

 ============================================
 SOCKET.IO SETUP
 ============================================

 Add the SocketIO-Client-Swift package:
 1. File > Add Package Dependencies
 2. URL: https://github.com/socketio/socket.io-client-swift
 3. Version: 16.1.0 or later

 ============================================
 */

/// Network service for real-time communication with the racing server
@MainActor
class NetworkService: ObservableObject {

    // MARK: - Configuration

    /// Server URL - Change this to your server address
    /// Local: "http://localhost:3000"
    /// ngrok: "https://xxxx-xx-xx-xx-xx.ngrok.io"
    /// Production: "https://your-server.railway.app"
    //static let serverURL = "https://pm5monitor-bfcjgxdwh3d7azgg.eastus-01.azurewebsites.net"
    //static let serverURL = "http://localhost:3000"
    //static let serverURL = "https://pm5raceserver-hffucbdhf9evcje3.eastus-01.azurewebsites.net"
    static let serverURL = "https://ce2b-2a02-3100-5805-9200-dd1b-b8c6-169c-b673.ngrok-free.app"

    // MARK: - Singleton

    static let shared = NetworkService()

    // MARK: - Published State

    @Published var isConnected = false
    @Published var lobbies: [ServerLobby] = []
    @Published var currentLobby: ServerLobby?
    @Published var currentRace: ServerRace?
    @Published var countdown: Int?
    @Published var error: NetworkError?

    // MARK: - User Identity

    /// The current user's ID, used for filtered lobby lists
    var userId: String?

    // MARK: - Socket.IO

    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private var isSocketConnected = false
    private var isManualDisconnect = false

    // MARK: - Fallback Polling

    private var pollingTimer: Timer?
    private let maxReconnectAttempts = 5

    // MARK: - Callbacks

    var onRaceStarted: ((ServerRace) -> Void)?
    var onRaceUpdate: ((ServerRace) -> Void)?
    var onRaceCompleted: ((ServerRace) -> Void)?
    var onCountdown: ((Int) -> Void)?

    // MARK: - Init

    private init() {}

    // MARK: - Socket.IO Setup

    private func setupSocket() {
        guard manager == nil else { return }

        guard let url = URL(string: Self.serverURL) else {
            print("NetworkService: Invalid server URL")
            return
        }

        manager = SocketManager(
            socketURL: url,
            config: [
                .log(false),
                .compress,
                .forceWebsockets(true),
                .reconnects(true),
                .reconnectAttempts(maxReconnectAttempts),
                .reconnectWait(2)
            ]
        )

        socket = manager?.defaultSocket
        setupSocketEventHandlers()
    }

    private func setupSocketEventHandlers() {
        guard let socket = socket else { return }

        // Connection events
        socket.on(clientEvent: .connect) { [weak self] _, _ in
            Task { @MainActor in
                self?.handleConnect()
            }
        }

        socket.on(clientEvent: .disconnect) { [weak self] data, _ in
            Task { @MainActor in
                self?.handleDisconnect(reason: data.first as? String)
            }
        }

        socket.on(clientEvent: .error) { [weak self] data, _ in
            Task { @MainActor in
                self?.handleError(data: data)
            }
        }

        socket.on(clientEvent: .reconnectAttempt) { data, _ in
            let attempt = data.first as? Int ?? 0
            print("NetworkService: Reconnect attempt \(attempt)")
        }

        // Server events - Lobby
        socket.on("lobbyList") { [weak self] data, _ in
            Task { @MainActor in
                self?.handleLobbyList(data: data)
            }
        }

        socket.on("lobbyCreated") { [weak self] data, _ in
            Task { @MainActor in
                self?.handleLobbyCreated(data: data)
            }
        }

        socket.on("lobbyUpdated") { [weak self] data, _ in
            Task { @MainActor in
                self?.handleLobbyUpdated(data: data)
            }
        }

        // Server events - Race
        socket.on("countdown") { [weak self] data, _ in
            Task { @MainActor in
                self?.handleCountdown(data: data)
            }
        }

        socket.on("raceStarted") { [weak self] data, _ in
            Task { @MainActor in
                self?.handleRaceStarted(data: data)
            }
        }

        socket.on("raceUpdate") { [weak self] data, _ in
            Task { @MainActor in
                self?.handleRaceUpdate(data: data)
            }
        }

        socket.on("raceCompleted") { [weak self] data, _ in
            Task { @MainActor in
                self?.handleRaceCompleted(data: data)
            }
        }
    }

    // MARK: - Connection Event Handlers

    private func handleConnect() {
        print("NetworkService: Socket connected")
        isSocketConnected = true
        isConnected = true

        // Stop fallback polling since socket is connected
        stopPolling()

        // Identify this socket with the user's ID for filtered lobby lists
        if let userId = userId {
            socket?.emit("identify", ["userId": userId])
        }

        // Request initial lobby list
        if let userId = userId {
            socket?.emit("getLobbies", ["userId": userId])
        } else {
            socket?.emit("getLobbies")
        }

        // Rejoin lobby room if we were in one
        if let lobby = currentLobby {
            print("NetworkService: Rejoining lobby \(lobby.id)")
            socket?.emit("rejoinLobby", ["lobbyId": lobby.id])
        }
    }

    private func handleDisconnect(reason: String?) {
        print("NetworkService: Socket disconnected - \(reason ?? "unknown")")
        isSocketConnected = false

        if !isManualDisconnect {
            // Start fallback polling
            startPolling()
        } else {
            isConnected = false
        }
    }

    private func handleError(data: [Any]) {
        print("NetworkService: Socket error - \(data)")
        error = .connectionFailed
    }

    // MARK: - Server Event Handlers

    private func handleLobbyList(data: [Any]) {
        guard let lobbyArray = data.first as? [[String: Any]] else {
            print("NetworkService: Failed to parse lobbyList")
            return
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: lobbyArray)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            lobbies = try decoder.decode([ServerLobby].self, from: jsonData)
        } catch {
            print("NetworkService: Failed to decode lobbyList - \(error)")
        }
    }

    private func handleLobbyCreated(data: [Any]) {
        guard let lobbyData = data.first as? [String: Any] else {
            print("NetworkService: Failed to parse lobbyCreated")
            return
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: lobbyData)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let lobby = try decoder.decode(ServerLobby.self, from: jsonData)
            currentLobby = lobby
        } catch {
            print("NetworkService: Failed to decode lobbyCreated - \(error)")
        }
    }

    private func handleLobbyUpdated(data: [Any]) {
        print("NetworkService: Received lobbyUpdated event")
        guard let lobbyData = data.first as? [String: Any] else {
            print("NetworkService: Failed to parse lobbyUpdated")
            return
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: lobbyData)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let lobby = try decoder.decode(ServerLobby.self, from: jsonData)

            print("NetworkService: lobbyUpdated for lobby \(lobby.id) with \(lobby.participants.count) participants")
            for p in lobby.participants {
                print("  - \(p.displayName): status=\(p.status), isBot=\(p.isBot ?? false)")
            }

            // Update currentLobby if this is our lobby
            if currentLobby?.id == lobby.id {
                print("NetworkService: Updating currentLobby")
                currentLobby = lobby
            }

            // Update in lobbies list
            if let index = lobbies.firstIndex(where: { $0.id == lobby.id }) {
                lobbies[index] = lobby
            }
        } catch {
            print("NetworkService: Failed to decode lobbyUpdated - \(error)")
        }
    }

    private func handleCountdown(data: [Any]) {
        guard let seconds = data.first as? Int else {
            print("NetworkService: Failed to parse countdown")
            return
        }

        countdown = seconds
        onCountdown?(seconds)
    }

    private func handleRaceStarted(data: [Any]) {
        guard let raceData = data.first as? [String: Any] else {
            print("NetworkService: Failed to parse raceStarted")
            return
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: raceData)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let race = try decoder.decode(ServerRace.self, from: jsonData)

            currentRace = race
            countdown = nil
            onRaceStarted?(race)
        } catch {
            print("NetworkService: Failed to decode raceStarted - \(error)")
        }
    }

    private func handleRaceUpdate(data: [Any]) {
        guard let raceData = data.first as? [String: Any] else {
            print("NetworkService: Failed to parse raceUpdate")
            return
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: raceData)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let race = try decoder.decode(ServerRace.self, from: jsonData)

            currentRace = race
            onRaceUpdate?(race)
        } catch {
            print("NetworkService: Failed to decode raceUpdate - \(error)")
        }
    }

    private func handleRaceCompleted(data: [Any]) {
        guard let raceData = data.first as? [String: Any] else {
            print("NetworkService: Failed to parse raceCompleted")
            return
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: raceData)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let race = try decoder.decode(ServerRace.self, from: jsonData)

            currentRace = race
            onRaceCompleted?(race)
        } catch {
            print("NetworkService: Failed to decode raceCompleted - \(error)")
        }
    }

    // MARK: - Connection

    func connect() {
        guard socket == nil || socket?.status != .connected else { return }

        isManualDisconnect = false
        setupSocket()

        print("NetworkService: Connecting to \(Self.serverURL)")
        socket?.connect()

        // Start fallback polling while socket connects
        startPolling()
    }

    func disconnect() {
        isManualDisconnect = true
        stopPolling()

        socket?.disconnect()
        socket?.removeAllHandlers()
        manager = nil
        socket = nil

        isSocketConnected = false
        isConnected = false
        currentLobby = nil
        currentRace = nil

        print("NetworkService: Disconnected")
    }

    /// Clear race state without disconnecting (used after race completion)
    func clearRaceState() {
        currentRace = nil
        currentLobby = nil
        print("NetworkService: Race state cleared")
    }

    // MARK: - Fallback Polling

    private func startPolling() {
        guard pollingTimer == nil else { return }

        // Poll for lobby updates every 2 seconds as fallback
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.fetchLobbies()
            }
        }

        // Initial fetch
        Task {
            await fetchLobbies()
        }

        isConnected = true
        print("NetworkService: Fallback polling started")
    }

    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    // MARK: - REST API Calls (Fallback)

    func fetchLobbies() async {
        var urlString = "\(Self.serverURL)/lobbies"
        if let userId = userId {
            urlString += "?userId=\(userId)"
        }
        guard let url = URL(string: urlString) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let fetchedLobbies = try decoder.decode([ServerLobby].self, from: data)
            self.lobbies = fetchedLobbies
        } catch {
            print("Failed to fetch lobbies: \(error)")
        }
    }

    func fetchLobby(id: String) async -> ServerLobby? {
        guard let url = URL(string: "\(Self.serverURL)/lobby/\(id)") else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ServerLobby.self, from: data)
        } catch {
            print("Failed to fetch lobby: \(error)")
            return nil
        }
    }

    // MARK: - Lobby Operations (Socket.IO with REST Fallback)

    func createLobby(
        creatorId: String,
        raceDistance: Int,
        entryFee: String,
        payoutMode: String,
        maxParticipants: Int
    ) async throws -> ServerLobby {
        if isSocketConnected, let socket = socket {
            return try await withCheckedThrowingContinuation { continuation in
                let data: [String: Any] = [
                    "creatorId": creatorId,
                    "raceDistance": raceDistance,
                    "entryFee": entryFee,
                    "payoutMode": payoutMode,
                    "maxParticipants": maxParticipants
                ]

                socket.once("lobbyCreated") { [weak self] responseData, _ in
                    guard let lobbyData = responseData.first as? [String: Any] else {
                        continuation.resume(throwing: NetworkError.decodingError)
                        return
                    }

                    do {
                        let jsonData = try JSONSerialization.data(withJSONObject: lobbyData)
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        let lobby = try decoder.decode(ServerLobby.self, from: jsonData)

                        Task { @MainActor in
                            self?.currentLobby = lobby
                        }
                        continuation.resume(returning: lobby)
                    } catch {
                        continuation.resume(throwing: NetworkError.decodingError)
                    }
                }

                socket.emit("createLobby", data)
            }
        } else {
            return try await createLobbyREST(
                creatorId: creatorId,
                raceDistance: raceDistance,
                entryFee: entryFee,
                payoutMode: payoutMode,
                maxParticipants: maxParticipants
            )
        }
    }

    func joinLobby(
        lobbyId: String,
        oderId: String,
        displayName: String,
        walletAddress: String,
        equipmentType: String
    ) async throws {
        if isSocketConnected, let socket = socket {
            return try await withCheckedThrowingContinuation { continuation in
                let participant: [String: Any] = [
                    "id": oderId,
                    "oderId": oderId,
                    "displayName": displayName,
                    "walletAddress": walletAddress,
                    "equipmentType": equipmentType
                ]

                let data: [String: Any] = [
                    "lobbyId": lobbyId,
                    "participant": participant
                ]

                socket.once("lobbyUpdated") { [weak self] responseData, _ in
                    guard let lobbyData = responseData.first as? [String: Any] else {
                        continuation.resume(throwing: NetworkError.decodingError)
                        return
                    }

                    do {
                        let jsonData = try JSONSerialization.data(withJSONObject: lobbyData)
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        let lobby = try decoder.decode(ServerLobby.self, from: jsonData)

                        Task { @MainActor in
                            self?.currentLobby = lobby
                        }
                        continuation.resume(returning: ())
                    } catch {
                        continuation.resume(throwing: NetworkError.decodingError)
                    }
                }

                socket.emit("joinLobby", data)
            }
        } else {
            try await joinLobbyREST(
                lobbyId: lobbyId,
                oderId: oderId,
                displayName: displayName,
                walletAddress: walletAddress,
                equipmentType: equipmentType
            )
        }
    }

    func addBot(lobbyId: String, difficulty: String) async throws {
        if isSocketConnected, let socket = socket {
            let data: [String: Any] = [
                "lobbyId": lobbyId,
                "difficulty": difficulty
            ]
            socket.emit("addBot", data)
            // Server will emit lobbyUpdated which we handle in event handler
        } else {
            try await addBotREST(lobbyId: lobbyId, difficulty: difficulty)
        }
    }

    func setReady(lobbyId: String, oderId: String) async throws {
        if isSocketConnected, let socket = socket {
            let data: [String: Any] = [
                "lobbyId": lobbyId,
                "oderId": oderId
            ]
            socket.emit("setReady", data)
            // Server will emit lobbyUpdated which we handle in event handler
        } else {
            try await setReadyREST(lobbyId: lobbyId, oderId: oderId)
        }
    }

    func leaveLobby(lobbyId: String, oderId: String) {
        if isSocketConnected, let socket = socket {
            let data: [String: Any] = [
                "lobbyId": lobbyId,
                "oderId": oderId
            ]
            socket.emit("leaveLobby", data)
        }
        currentLobby = nil
    }

    func startRace(lobbyId: String) async throws -> ServerRace {
        if isSocketConnected, let socket = socket {
            return try await withCheckedThrowingContinuation { continuation in
                socket.once("raceStarted") { [weak self] responseData, _ in
                    guard let raceData = responseData.first as? [String: Any] else {
                        continuation.resume(throwing: NetworkError.decodingError)
                        return
                    }

                    do {
                        let jsonData = try JSONSerialization.data(withJSONObject: raceData)
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        let race = try decoder.decode(ServerRace.self, from: jsonData)

                        Task { @MainActor in
                            self?.currentRace = race
                        }
                        continuation.resume(returning: race)
                    } catch {
                        continuation.resume(throwing: NetworkError.decodingError)
                    }
                }

                socket.emit("startRace", ["lobbyId": lobbyId])
            }
        } else {
            return try await startRaceREST(lobbyId: lobbyId)
        }
    }

    func sendRaceUpdate(raceId: String, oderId: String, distance: Double, pace: Double, watts: Int) async {
        if isSocketConnected, let socket = socket {
            let metrics: [String: Any] = [
                "distance": distance,
                "pace": pace,
                "watts": watts
            ]

            let data: [String: Any] = [
                "raceId": raceId,
                "oderId": oderId,
                "metrics": metrics
            ]

            socket.emit("raceUpdate", data)
        } else {
            await sendRaceUpdateREST(raceId: raceId, oderId: oderId, distance: distance, pace: pace, watts: watts)
        }
    }

    // MARK: - User Profile (Firestore via Server)

    /// Fetch user profile from server (backed by Firestore)
    func fetchUserProfile(userId: String) async -> UserProfile? {
        guard let url = URL(string: "\(Self.serverURL)/api/user/\(userId)/profile") else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(UserProfile.self, from: data)
        } catch {
            print("NetworkService: Failed to fetch user profile: \(error)")
            return nil
        }
    }

    /// Save user profile to server (persisted in Firestore)
    func saveUserProfile(userId: String, displayName: String, email: String?, walletAddress: String?) async {
        guard let url = URL(string: "\(Self.serverURL)/api/user/\(userId)/profile") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = ["displayName": displayName]
        if let email = email { body["email"] = email }
        if let walletAddress = walletAddress { body["walletAddress"] = walletAddress }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (_, _) = try await URLSession.shared.data(for: request)
            print("NetworkService: User profile saved for \(userId)")
        } catch {
            print("NetworkService: Failed to save user profile: \(error)")
        }
    }

    // MARK: - REST API Fallback Methods

    private func createLobbyREST(
        creatorId: String,
        raceDistance: Int,
        entryFee: String,
        payoutMode: String,
        maxParticipants: Int
    ) async throws -> ServerLobby {
        guard let url = URL(string: "\(Self.serverURL)/api/lobby") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "creatorId": creatorId,
            "raceDistance": raceDistance,
            "entryFee": entryFee,
            "payoutMode": payoutMode,
            "maxParticipants": maxParticipants
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let lobby = try decoder.decode(ServerLobby.self, from: data)

        currentLobby = lobby
        await fetchLobbies()

        return lobby
    }

    private func joinLobbyREST(
        lobbyId: String,
        oderId: String,
        displayName: String,
        walletAddress: String,
        equipmentType: String
    ) async throws {
        guard let url = URL(string: "\(Self.serverURL)/api/lobby/\(lobbyId)/join") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "id": oderId,
            "oderId": oderId,
            "displayName": displayName,
            "walletAddress": walletAddress,
            "equipmentType": equipmentType
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        currentLobby = try decoder.decode(ServerLobby.self, from: data)

        // Join Socket.IO room if socket is connected (REST join doesn't add to room)
        if isSocketConnected, let socket = socket {
            print("NetworkService: Joining socket room after REST join")
            socket.emit("rejoinLobby", ["lobbyId": lobbyId])
        }
    }

    private func addBotREST(lobbyId: String, difficulty: String) async throws {
        guard let url = URL(string: "\(Self.serverURL)/api/lobby/\(lobbyId)/bot") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["difficulty": difficulty]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        currentLobby = try decoder.decode(ServerLobby.self, from: data)

        await fetchLobbies()
    }

    private func setReadyREST(lobbyId: String, oderId: String) async throws {
        guard let url = URL(string: "\(Self.serverURL)/api/lobby/\(lobbyId)/ready") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["oderId": oderId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        currentLobby = try decoder.decode(ServerLobby.self, from: data)
    }

    private func startRaceREST(lobbyId: String) async throws -> ServerRace {
        guard let url = URL(string: "\(Self.serverURL)/api/lobby/\(lobbyId)/start") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (data, _) = try await URLSession.shared.data(for: request)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let race = try decoder.decode(ServerRace.self, from: data)

        currentRace = race
        return race
    }

    private func sendRaceUpdateREST(raceId: String, oderId: String, distance: Double, pace: Double, watts: Int) async {
        guard let url = URL(string: "\(Self.serverURL)/api/race/\(raceId)/update") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "oderId": oderId,
            "distance": distance,
            "pace": pace,
            "watts": watts
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoder = JSONDecoder()
            currentRace = try decoder.decode(ServerRace.self, from: data)
        } catch {
            print("Failed to send race update: \(error)")
        }
    }
}

// MARK: - Server Models

struct ServerLobby: Codable, Identifiable {
    let id: String
    let creatorId: String
    let raceDistance: Int
    let entryFee: String
    let payoutMode: String
    let status: String
    let maxParticipants: Int
    let minParticipants: Int
    let createdAt: String
    var participants: [ServerParticipant]
    var participantCount: Int?
    var raceId: String?
    var raceResults: [ServerRaceResult]?

    var displayParticipantCount: Int {
        participantCount ?? participants.count
    }

    var isCompleted: Bool {
        status == "completed"
    }
}

struct ServerRaceResult: Codable, Identifiable {
    let oderId: String
    let displayName: String
    var walletAddress: String?
    var position: Int?
    var finishTime: Double?
    var distance: Double
    var pace: Double
    var watts: Int
    var isBot: Bool?
    var isFinished: Bool

    var id: String { oderId }
}

struct ServerParticipant: Codable, Identifiable {
    let id: String
    let oderId: String
    let displayName: String
    let walletAddress: String
    let equipmentType: String
    var status: String
    let isBot: Bool?
    let botDifficulty: String?
    let joinedAt: String

    var equipment: EquipmentType {
        EquipmentType(rawValue: equipmentType) ?? .rower
    }

    var isReady: Bool {
        status == "ready"
    }
}

struct ServerRace: Codable, Identifiable {
    let id: String
    let lobbyId: String
    var status: String
    let targetDistance: Int
    var participants: [ServerRaceParticipant]
    var finishedCount: Int
}

struct ServerRaceParticipant: Codable, Identifiable {
    let id: String
    let oderId: String
    let displayName: String
    let equipmentType: String
    let isBot: Bool?
    let botDifficulty: String?
    var distance: Double
    var pace: Double
    var watts: Int
    var isFinished: Bool
    var finishTime: Double?
    var position: Int?

    var equipment: EquipmentType {
        EquipmentType(rawValue: equipmentType) ?? .rower
    }
}

// MARK: - Network Error

enum NetworkError: LocalizedError {
    case invalidURL
    case connectionFailed
    case serverError(String)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .connectionFailed:
            return "Failed to connect to server"
        case .serverError(let message):
            return message
        case .decodingError:
            return "Failed to decode server response"
        }
    }
}
