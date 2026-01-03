import Foundation
import Combine

// import FirebaseFirestore

@MainActor
class RaceService: ObservableObject {

    // MARK: - Published State

    @Published var raceState: RaceState = .idle
    @Published var currentRace: Race?
    @Published var participants: [RaceParticipant] = []
    @Published var myProgress: RaceProgress?
    @Published var myEquipmentType: EquipmentType = .rower
    @Published var countdown: Int?
    @Published var error: RaceError?

    // MARK: - Private

    // private let db = Firestore.firestore()
    // private var raceListener: ListenerRegistration?
    // private var updatesListener: ListenerRegistration?
    private var updateTimer: Timer?
    private var lastUpdateTime: Date = .distantPast
    private let updateInterval: TimeInterval = 0.5 // 2 Hz

    // MARK: - Race Lifecycle

    /// Start a race from a lobby
    func startRace(lobbyId: String, participantIds: [String]) async throws -> Race {
        let raceId = UUID().uuidString
        let race = Race(
            id: raceId,
            lobbyId: lobbyId,
            status: .active,
            startTime: Date(),
            targetDistance: 5000 // Will be fetched from lobby
        )

        // Firebase implementation:
        // try await db.collection("races").document(raceId).setData(from: race)
        //
        // Update lobby status
        // try await db.collection("lobbies").document(lobbyId).updateData([
        //     "status": LobbyStatus.inProgress.rawValue,
        //     "startedAt": FieldValue.serverTimestamp()
        // ])

        currentRace = race
        raceState = .countdown(seconds: 5)

        // Start countdown
        await startCountdown()

        return race
    }

    /// Start countdown before race
    private func startCountdown() async {
        for i in stride(from: 5, through: 1, by: -1) {
            countdown = i
            raceState = .countdown(seconds: i)
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        }

        countdown = nil
        raceState = .racing
        startUpdateTimer()
    }

    /// Subscribe to race updates
    func subscribeToRace(_ raceId: String) {
        // Firebase implementation:
        // raceListener = db.collection("races").document(raceId)
        //     .addSnapshotListener { [weak self] snapshot, error in
        //         guard let self = self, let snapshot = snapshot else { return }
        //         Task { @MainActor in
        //             self.currentRace = try? snapshot.data(as: Race.self)
        //         }
        //     }
        //
        // Subscribe to participant updates
        // updatesListener = db.collection("races").document(raceId)
        //     .collection("updates")
        //     .order(by: "timestamp", descending: true)
        //     .limit(to: 20) // Latest updates per participant
        //     .addSnapshotListener { [weak self] snapshot, error in
        //         guard let self = self, let snapshot = snapshot else { return }
        //         Task { @MainActor in
        //             self.processUpdates(snapshot.documents)
        //         }
        //     }
    }

    /// Unsubscribe from race
    func unsubscribe() {
        // raceListener?.remove()
        // updatesListener?.remove()
        stopUpdateTimer()
        currentRace = nil
        participants = []
        raceState = .idle
    }

    // MARK: - Position Updates

    /// Send current metrics to server (throttled)
    func sendUpdate(participantId: String, metrics: RowingMetrics) async throws {
        // Throttle updates
        let now = Date()
        guard now.timeIntervalSince(lastUpdateTime) >= updateInterval else { return }
        lastUpdateTime = now

        let update = RaceUpdate(participantId: participantId, metrics: metrics)

        // Firebase implementation:
        // try await db.collection("races").document(currentRace!.id)
        //     .collection("updates")
        //     .addDocument(from: update)

        // Update local progress
        updateMyProgress(metrics: metrics)

        // Check for race completion
        if let race = currentRace {
            checkCompletion(
                currentDistance: metrics.distance,
                targetDistance: Double(race.targetDistance)
            )
        }
    }

    /// Update local progress tracker
    private func updateMyProgress(metrics: RowingMetrics) {
        guard let race = currentRace else { return }

        myProgress = RaceProgress(
            distance: metrics.distance,
            targetDistance: Double(race.targetDistance),
            elapsedTime: metrics.elapsedTime,
            currentPace: metrics.pace,
            positionInRace: calculatePosition(distance: metrics.distance),
            totalParticipants: participants.count
        )
    }

    /// Calculate current position based on distance
    private func calculatePosition(distance: Double) -> Int {
        let aheadCount = participants.filter { $0.distance > distance }.count
        return aheadCount + 1
    }

    /// Check if race is complete
    private func checkCompletion(currentDistance: Double, targetDistance: Double) {
        if currentDistance >= targetDistance {
            finishRace()
        }
    }

    /// Handle race finish
    private func finishRace() {
        stopUpdateTimer()

        let position = calculatePosition(distance: myProgress?.distance ?? 0)
        raceState = .finished(position: position)

        // Firebase implementation:
        // Submit final result
        // try await submitResult(...)
    }

    // MARK: - Results

    /// Submit final race result
    func submitResult(participantId: String, finalMetrics: RowingMetrics, walletAddress: String) async throws {
        guard let race = currentRace else {
            throw RaceError.notInRace
        }

        let result = RaceResult(
            id: participantId,
            position: 0, // Will be calculated server-side
            finalTime: finalMetrics.elapsedTime,
            avgWatts: finalMetrics.avgWatts,
            avgPace: finalMetrics.pace,
            payout: "0", // Will be calculated server-side
            walletAddress: walletAddress
        )

        // Firebase implementation:
        // try await db.collection("races").document(race.id)
        //     .collection("results").document(participantId)
        //     .setData(from: result)
    }

    /// Fetch race results
    func fetchResults(raceId: String) async throws -> [RaceResult] {
        // Firebase implementation:
        // let snapshot = try await db.collection("races").document(raceId)
        //     .collection("results")
        //     .order(by: "position")
        //     .getDocuments()
        //
        // return snapshot.documents.compactMap { doc in
        //     try? doc.data(as: RaceResult.self)
        // }

        return []
    }

    // MARK: - Timer

    private func startUpdateTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            // Timer tick - UI can use this to refresh
        }
    }

    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    // MARK: - Validation

    /// Validate metrics for anti-cheat
    func validateMetrics(_ metrics: RowingMetrics, previous: RowingMetrics?) -> Bool {
        // Basic validation checks
        guard metrics.watts >= 0 && metrics.watts < 2000 else { return false }
        guard metrics.strokeRate >= 0 && metrics.strokeRate < 100 else { return false }
        guard metrics.pace >= 0 && metrics.pace < 600 else { return false } // Max 10 min pace

        // Check progression consistency
        if let previous = previous {
            let timeDelta = metrics.elapsedTime - previous.elapsedTime
            let distanceDelta = metrics.distance - previous.distance

            // Can't go backwards
            guard distanceDelta >= 0 else { return false }

            // Check reasonable speed (max ~7 m/s)
            if timeDelta > 0 {
                let speed = distanceDelta / timeDelta
                guard speed < 7.0 else { return false }
            }
        }

        return true
    }
}

// MARK: - Race Error

enum RaceError: LocalizedError {
    case notInRace
    case raceNotStarted
    case raceAlreadyFinished
    case invalidMetrics
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .notInRace:
            return "You are not in a race"
        case .raceNotStarted:
            return "The race has not started yet"
        case .raceAlreadyFinished:
            return "The race has already finished"
        case .invalidMetrics:
            return "Invalid metrics detected"
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}
