import Foundation

// import FirebaseFirestore

@MainActor
class LobbyService: ObservableObject {

    // MARK: - Published State

    @Published var availableLobbies: [Lobby] = []
    @Published var currentLobby: Lobby?
    @Published var participants: [LobbyParticipant] = []
    @Published var isLoading = false
    @Published var error: LobbyError?

    // MARK: - Private

    // private let db = Firestore.firestore()
    // private var lobbyListener: ListenerRegistration?
    // private var participantsListener: ListenerRegistration?

    // MARK: - Lobby Creation

    /// Create a new lobby
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

        let lobbyId = UUID().uuidString
        let lobby = Lobby(
            id: lobbyId,
            creatorId: creatorId,
            raceDistance: distance.rawValue,
            entryFee: entryFee.weiAmount,
            payoutMode: payoutMode,
            maxParticipants: maxParticipants,
            minParticipants: minParticipants
        )

        // Firebase implementation:
        // try await db.collection("lobbies").document(lobbyId).setData(from: lobby)

        currentLobby = lobby
        return lobby
    }

    // MARK: - Lobby Discovery

    /// Fetch available lobbies
    func fetchAvailableLobbies() async throws {
        isLoading = true
        error = nil

        defer { isLoading = false }

        // Firebase implementation:
        // let snapshot = try await db.collection("lobbies")
        //     .whereField("status", isEqualTo: LobbyStatus.waiting.rawValue)
        //     .order(by: "createdAt", descending: true)
        //     .limit(to: 50)
        //     .getDocuments()
        //
        // availableLobbies = snapshot.documents.compactMap { doc in
        //     try? doc.data(as: Lobby.self)
        // }

        // Mock implementation
        #if DEBUG
        availableLobbies = [
            Lobby(
                id: "mock-1",
                creatorId: "user-1",
                raceDistance: 5000,
                entryFee: "1000000", // 1 USDC
                payoutMode: .winnerTakesAll,
                participantCount: 3
            ),
            Lobby(
                id: "mock-2",
                creatorId: "user-2",
                raceDistance: 10000,
                entryFee: "5000000", // 5 USDC
                payoutMode: .topThree,
                participantCount: 5
            )
        ]
        #endif
    }

    /// Subscribe to real-time lobby updates
    func subscribeToLobbies() {
        // Firebase implementation:
        // lobbyListener = db.collection("lobbies")
        //     .whereField("status", isEqualTo: LobbyStatus.waiting.rawValue)
        //     .addSnapshotListener { [weak self] snapshot, error in
        //         guard let self = self, let snapshot = snapshot else { return }
        //         Task { @MainActor in
        //             self.availableLobbies = snapshot.documents.compactMap { doc in
        //                 try? doc.data(as: Lobby.self)
        //             }
        //         }
        //     }
    }

    /// Unsubscribe from lobby updates
    func unsubscribe() {
        // lobbyListener?.remove()
        // participantsListener?.remove()
        currentLobby = nil
        participants = []
    }

    // MARK: - Lobby Participation

    /// Join an existing lobby
    func joinLobby(_ lobbyId: String, userId: String, displayName: String, walletAddress: String) async throws {
        isLoading = true
        error = nil

        defer { isLoading = false }

        // Firebase implementation:
        // Check if lobby exists and is not full
        // let lobbyDoc = try await db.collection("lobbies").document(lobbyId).getDocument()
        // guard let lobby = try? lobbyDoc.data(as: Lobby.self),
        //       lobby.status == .waiting,
        //       !lobby.isFull else {
        //     throw LobbyError.lobbyNotAvailable
        // }
        //
        // Add participant
        // let participant = LobbyParticipant(...)
        // try await db.collection("lobbies").document(lobbyId)
        //     .collection("participants").document(userId).setData(from: participant)
        //
        // Increment participant count
        // try await db.collection("lobbies").document(lobbyId).updateData([
        //     "participantCount": FieldValue.increment(Int64(1))
        // ])

        // Mock implementation
        #if DEBUG
        if let lobby = availableLobbies.first(where: { $0.id == lobbyId }) {
            currentLobby = lobby
            let participant = LobbyParticipant(
                id: userId,
                oderId: userId,
                displayName: displayName,
                walletAddress: walletAddress,
                status: .deposited,
                joinedAt: Date()
            )
            participants = [participant]
        }
        #endif
    }

    /// Leave current lobby
    func leaveLobby() async throws {
        guard let lobby = currentLobby else { return }

        // Firebase implementation:
        // Remove participant document
        // Decrement participant count

        currentLobby = nil
        participants = []
    }

    /// Mark as ready
    func setReady(userId: String) async throws {
        guard let lobby = currentLobby else {
            throw LobbyError.notInLobby
        }

        // Firebase implementation:
        // try await db.collection("lobbies").document(lobby.id)
        //     .collection("participants").document(userId)
        //     .updateData(["status": ParticipantStatus.ready.rawValue])

        // Update local state
        if let index = participants.firstIndex(where: { $0.id == userId }) {
            participants[index].status = .ready
        }
    }

    /// Subscribe to participants in current lobby
    func subscribeToParticipants(lobbyId: String) {
        // Firebase implementation:
        // participantsListener = db.collection("lobbies").document(lobbyId)
        //     .collection("participants")
        //     .addSnapshotListener { [weak self] snapshot, error in
        //         guard let self = self, let snapshot = snapshot else { return }
        //         Task { @MainActor in
        //             self.participants = snapshot.documents.compactMap { doc in
        //                 try? doc.data(as: LobbyParticipant.self)
        //             }
        //         }
        //     }
    }

    // MARK: - Matchmaking

    /// Find a match based on skill level
    func findMatch(
        userId: String,
        distance: RaceDistance,
        entryFee: EntryFeePreset,
        skillRating: Int
    ) async throws -> Lobby? {
        isLoading = true
        error = nil

        defer { isLoading = false }

        // Calculate skill range (±200)
        let skillRange = SkillRange(min: skillRating - 200, max: skillRating + 200)

        // Firebase implementation:
        // Query for matching lobbies
        // let snapshot = try await db.collection("lobbies")
        //     .whereField("status", isEqualTo: LobbyStatus.waiting.rawValue)
        //     .whereField("raceDistance", isEqualTo: distance.rawValue)
        //     .whereField("entryFee", isEqualTo: entryFee.weiAmount)
        //     .limit(to: 10)
        //     .getDocuments()
        //
        // Filter by skill range
        // let matching = snapshot.documents.compactMap { ... }
        // return matching.first

        // Mock: create a new lobby if none found
        return nil
    }

    // MARK: - Start Race

    /// Start the race (creator only)
    func startRace() async throws -> String {
        guard let lobby = currentLobby else {
            throw LobbyError.notInLobby
        }

        guard lobby.canStart else {
            throw LobbyError.notEnoughParticipants
        }

        // Firebase implementation:
        // Update lobby status to starting
        // Create race document
        // Return race ID

        let raceId = UUID().uuidString
        return raceId
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
