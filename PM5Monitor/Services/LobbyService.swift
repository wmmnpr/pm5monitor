import Foundation

@MainActor
class LobbyService: ObservableObject {

    // MARK: - Published State

    @Published var availableLobbies: [Lobby] = []
    @Published var currentLobby: Lobby?
    @Published var participants: [LobbyParticipant] = []
    @Published var isLoading = false
    @Published var error: LobbyError?

    // MARK: - Private

    private let networkService = NetworkService.shared
    private var pollingTimer: Timer?

    // MARK: - Init

    init() {
        networkService.connect()
    }

    // MARK: - Lobby Creation

    func createLobby(
        creatorId: String,
        distance: RaceDistance,
        entryFee: EntryFeePreset,
        payoutMode: PayoutMode,
        maxParticipants: Int = 10,
        minParticipants: Int = 2
    ) async throws -> Lobby {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let serverLobby = try await networkService.createLobby(
                creatorId: creatorId,
                raceDistance: distance.rawValue,
                entryFee: entryFee.weiAmount,
                payoutMode: payoutMode.rawValue,
                maxParticipants: maxParticipants
            )

            let lobby = convertServerLobby(serverLobby)
            currentLobby = lobby

            // Refresh lobby list
            await fetchAvailableLobbies()

            return lobby
        } catch {
            self.error = .unknown(error)
            throw error
        }
    }

    // MARK: - Lobby Discovery

    func fetchAvailableLobbies() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        await networkService.fetchLobbies()
        availableLobbies = networkService.lobbies.map { convertServerLobby($0) }
    }

    func subscribeToLobbies() {
        // Start polling for updates
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.fetchAvailableLobbies()
            }
        }

        Task {
            await fetchAvailableLobbies()
        }
    }

    func unsubscribe() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        currentLobby = nil
        participants = []
    }

    // MARK: - Lobby Participation

    func joinLobby(
        _ lobbyId: String,
        userId: String,
        displayName: String,
        walletAddress: String,
        equipmentType: EquipmentType
    ) async throws {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            try await networkService.joinLobby(
                lobbyId: lobbyId,
                oderId: userId,
                displayName: displayName,
                walletAddress: walletAddress,
                equipmentType: equipmentType.rawValue
            )

            if let serverLobby = networkService.currentLobby {
                currentLobby = convertServerLobby(serverLobby)
                participants = serverLobby.participants.map { convertServerParticipant($0) }
            }

            await fetchAvailableLobbies()
        } catch {
            self.error = .unknown(error)
            throw error
        }
    }

    func leaveLobby() async throws {
        currentLobby = nil
        participants = []
    }

    func setReady(userId: String) async throws {
        guard let lobby = currentLobby else {
            throw LobbyError.notInLobby
        }

        try await networkService.setReady(lobbyId: lobby.id, oderId: userId)

        if let serverLobby = networkService.currentLobby {
            currentLobby = convertServerLobby(serverLobby)
            participants = serverLobby.participants.map { convertServerParticipant($0) }
        }
    }

    // MARK: - Bot Management

    func addBot(difficulty: BotDifficulty) async throws {
        guard let lobby = currentLobby else {
            throw LobbyError.notInLobby
        }

        try await networkService.addBot(lobbyId: lobby.id, difficulty: difficulty.rawValue)

        if let serverLobby = networkService.currentLobby {
            currentLobby = convertServerLobby(serverLobby)
            participants = serverLobby.participants.map { convertServerParticipant($0) }
        }
    }

    // MARK: - Subscribe to Participants

    func subscribeToParticipants(lobbyId: String) {
        // Poll for participant updates
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if let serverLobby = await self.networkService.fetchLobby(id: lobbyId) {
                    self.currentLobby = self.convertServerLobby(serverLobby)
                    self.participants = serverLobby.participants.map { self.convertServerParticipant($0) }
                }
            }
        }
    }

    // MARK: - Start Race

    func startRace() async throws -> String {
        guard let lobby = currentLobby else {
            throw LobbyError.notInLobby
        }

        guard lobby.canStart else {
            throw LobbyError.notEnoughParticipants
        }

        let race = try await networkService.startRace(lobbyId: lobby.id)
        return race.id
    }

    // MARK: - Conversion Helpers

    private func convertServerLobby(_ server: ServerLobby) -> Lobby {
        Lobby(
            id: server.id,
            creatorId: server.creatorId,
            raceDistance: server.raceDistance,
            entryFee: server.entryFee,
            payoutMode: PayoutMode(rawValue: server.payoutMode) ?? .winnerTakesAll,
            status: LobbyStatus(rawValue: server.status) ?? .waiting,
            maxParticipants: server.maxParticipants,
            minParticipants: server.minParticipants,
            participantCount: server.displayParticipantCount
        )
    }

    private func convertServerParticipant(_ server: ServerParticipant) -> LobbyParticipant {
        LobbyParticipant(
            id: server.id,
            userId: server.oderId,
            displayName: server.displayName,
            walletAddress: server.walletAddress,
            equipmentType: server.equipment,
            status: ParticipantStatus(rawValue: server.status) ?? .deposited,
            joinedAt: ISO8601DateFormatter().date(from: server.joinedAt) ?? Date()
        )
    }

    // MARK: - Quick Match

    func findMatch(
        userId: String,
        distance: RaceDistance,
        entryFee: EntryFeePreset,
        skillRating: Int
    ) async throws -> Lobby? {
        // Look for an existing lobby with matching criteria
        await fetchAvailableLobbies()

        // Find a matching lobby
        if let matchingLobby = availableLobbies.first(where: { lobby in
            lobby.raceDistance == distance.rawValue &&
            lobby.entryFee == entryFee.weiAmount &&
            !lobby.isFull &&
            lobby.status == .waiting
        }) {
            return matchingLobby
        }

        // No matching lobby found - could create one automatically
        return nil
    }
}

// MARK: - Bot Difficulty

enum BotDifficulty: String, CaseIterable, Identifiable {
    case easy = "easy"
    case medium = "medium"
    case hard = "hard"
    case elite = "elite"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .easy: return "Easy"
        case .medium: return "Medium"
        case .hard: return "Hard"
        case .elite: return "Elite"
        }
    }

    var description: String {
        switch self {
        case .easy: return "2:30/500m pace, ~120W"
        case .medium: return "2:00/500m pace, ~180W"
        case .hard: return "1:40/500m pace, ~250W"
        case .elite: return "1:30/500m pace, ~320W"
        }
    }
}

// MARK: - Lobby Error

enum LobbyError: LocalizedError {
    case lobbyNotAvailable
    case notInLobby
    case notEnoughParticipants
    case alreadyInLobby
    case notCreator
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .lobbyNotAvailable:
            return "This lobby is no longer available"
        case .notInLobby:
            return "You are not in a lobby"
        case .notEnoughParticipants:
            return "Not enough participants to start"
        case .alreadyInLobby:
            return "You are already in a lobby"
        case .notCreator:
            return "Only the creator can perform this action"
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}
