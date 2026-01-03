import Foundation

/// Status of a race
enum RaceStatus: String, Codable {
    case active = "active"
    case completed = "completed"
}

/// A race in progress or completed
struct Race: Codable, Identifiable {
    let id: String
    let lobbyId: String
    var status: RaceStatus
    var startTime: Date
    var endTime: Date?
    var targetDistance: Int
    var winnerId: String?
    var payoutTxHash: String?

    /// Race distance as enum
    var distance: RaceDistance? {
        RaceDistance(rawValue: targetDistance)
    }

    /// Duration of the race
    var duration: TimeInterval? {
        guard let endTime = endTime else { return nil }
        return endTime.timeIntervalSince(startTime)
    }
}

/// A participant's state during a race
struct RaceParticipant: Identifiable {
    let id: String
    let userId: String
    var displayName: String
    var equipmentType: EquipmentType
    var distance: Double
    var pace: TimeInterval
    var watts: Int
    var isFinished: Bool
    var finishTime: TimeInterval?
    var position: Int?

    /// Progress toward target distance (0.0 - 1.0)
    func progress(toward targetDistance: Double) -> Double {
        guard targetDistance > 0 else { return 0 }
        return min(distance / targetDistance, 1.0)
    }
}

/// Real-time race progress for the current user
struct RaceProgress {
    var distance: Double
    var targetDistance: Double
    var elapsedTime: TimeInterval
    var currentPace: TimeInterval
    var positionInRace: Int
    var totalParticipants: Int

    /// Progress percentage (0.0 - 1.0)
    var percentComplete: Double {
        guard targetDistance > 0 else { return 0 }
        return min(distance / targetDistance, 1.0)
    }

    /// Remaining distance in meters
    var remainingDistance: Double {
        max(targetDistance - distance, 0)
    }

    /// Estimated time to finish based on current pace
    var estimatedTimeToFinish: TimeInterval? {
        guard currentPace > 0, remainingDistance > 0 else { return nil }
        // Pace is per 500m, so calculate time for remaining distance
        return (remainingDistance / 500.0) * currentPace
    }
}

/// Race state machine
enum RaceState: Equatable {
    case idle
    case inLobby(lobbyId: String)
    case countdown(seconds: Int)
    case racing
    case finished(position: Int)
    case cancelled

    var isRacing: Bool {
        if case .racing = self { return true }
        return false
    }

    var isInLobby: Bool {
        if case .inLobby = self { return true }
        return false
    }
}

/// Final race result for a participant
struct RaceResult: Codable, Identifiable {
    let id: String // participantId
    var position: Int
    var finalTime: TimeInterval
    var avgWatts: Int
    var avgPace: TimeInterval
    var payout: String // wei
    var walletAddress: String

    /// Payout in ETH
    var payoutETH: Double {
        guard let wei = Double(payout) else { return 0 }
        return wei / 1_000_000_000_000_000_000
    }
}

// MARK: - Race Update (sent to server)

struct RaceUpdate: Codable {
    let participantId: String
    let distance: Double
    let pace: TimeInterval
    let watts: Int
    let timestamp: Date

    init(participantId: String, metrics: RowingMetrics) {
        self.participantId = participantId
        self.distance = metrics.distance
        self.pace = metrics.pace
        self.watts = metrics.watts
        self.timestamp = Date()
    }
}

// MARK: - Prize Distribution

struct PrizeDistribution {
    /// Calculate payouts for winner-takes-all mode
    static func winnerTakesAll(prizePool: Double) -> [Double] {
        [prizePool]
    }

    /// Calculate payouts for top 3 mode (60/30/10)
    static func topThree(prizePool: Double) -> [Double] {
        [
            prizePool * 0.60,
            prizePool * 0.30,
            prizePool * 0.10
        ]
    }

    /// Get payouts based on mode
    static func calculate(mode: PayoutMode, totalPool: Double) -> [Double] {
        let prizePool = PlatformFee.prizePool(from: totalPool)

        switch mode {
        case .winnerTakesAll:
            return winnerTakesAll(prizePool: prizePool)
        case .topThree:
            return topThree(prizePool: prizePool)
        }
    }
}
