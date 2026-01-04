import Foundation
import Combine

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
 */

/// Network service for real-time communication with the racing server
@MainActor
class NetworkService: ObservableObject {

    // MARK: - Configuration

    /// Server URL - Change this to your server address
    /// Local: "http://localhost:3000"
    /// ngrok: "https://xxxx-xx-xx-xx-xx.ngrok.io"
    /// Production: "https://your-server.railway.app"
    static let serverURL = "http://localhost:3000"

    // MARK: - Singleton

    static let shared = NetworkService()

    // MARK: - Published State

    @Published var isConnected = false
    @Published var lobbies: [ServerLobby] = []
    @Published var currentLobby: ServerLobby?
    @Published var currentRace: ServerRace?
    @Published var countdown: Int?
    @Published var error: NetworkError?

    // MARK: - Private

    private var webSocketTask: URLSessionWebSocketTask?
    private var pingTimer: Timer?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5

    // MARK: - Callbacks

    var onRaceStarted: ((ServerRace) -> Void)?
    var onRaceUpdate: ((ServerRace) -> Void)?
    var onRaceCompleted: ((ServerRace) -> Void)?
    var onCountdown: ((Int) -> Void)?

    // MARK: - Init

    private init() {}

    // MARK: - Connection

    func connect() {
        guard webSocketTask == nil else { return }

        // For Socket.IO, we use polling fallback since native WebSocket
        // doesn't support Socket.IO protocol directly.
        // In production, add SocketIO-Client-Swift package

        // For now, use REST polling + WebSocket for updates
        startPolling()
        isConnected = true

        print("NetworkService: Connected to \(Self.serverURL)")
    }

    func disconnect() {
        stopPolling()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
    }

    // MARK: - Polling (Simple approach without Socket.IO package)

    private var pollingTimer: Timer?

    private func startPolling() {
        // Poll for lobby updates every 2 seconds
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.fetchLobbies()
            }
        }

        // Initial fetch
        Task {
            await fetchLobbies()
        }
    }

    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    // MARK: - REST API Calls

    func fetchLobbies() async {
        guard let url = URL(string: "\(Self.serverURL)/lobbies") else { return }

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

    // MARK: - Socket.IO Style Events (via HTTP for simplicity)

    func createLobby(
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

    func joinLobby(
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
    }

    func addBot(lobbyId: String, difficulty: String) async throws {
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

    func setReady(lobbyId: String, oderId: String) async throws {
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

    func startRace(lobbyId: String) async throws -> ServerRace {
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

    func sendRaceUpdate(raceId: String, oderId: String, distance: Double, pace: Double, watts: Int) async {
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

    var displayParticipantCount: Int {
        participantCount ?? participants.count
    }
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
