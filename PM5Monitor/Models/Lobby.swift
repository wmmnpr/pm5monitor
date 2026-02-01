import Foundation

/// Payout distribution mode for the race
enum PayoutMode: String, Codable, CaseIterable {
    case winnerTakesAll = "winner_takes_all"
    case topThree = "top_three"

    var displayName: String {
        switch self {
        case .winnerTakesAll: return "Winner Takes All"
        case .topThree: return "Top 3 Payout"
        }
    }

    var description: String {
        switch self {
        case .winnerTakesAll:
            return "1st place receives 95% of the pool"
        case .topThree:
            return "1st: 57%, 2nd: 28.5%, 3rd: 9.5%"
        }
    }
}

/// Status of a lobby
enum LobbyStatus: String, Codable {
    case waiting = "waiting"
    case starting = "starting"
    case inProgress = "in_progress"
    case completed = "completed"
    case cancelled = "cancelled"
}

/// A race lobby that players can join
struct Lobby: Codable, Identifiable, Hashable {
    static func == (lhs: Lobby, rhs: Lobby) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    let id: String
    let creatorId: String
    var raceDistance: Int // meters (350, 500, 1000, 2000, 5000, 10000)
    var entryFee: String // wei (stored as string for precision)
    var payoutMode: PayoutMode
    var status: LobbyStatus
    var maxParticipants: Int
    var minParticipants: Int
    var skillRange: SkillRange?
    var createdAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var escrowTxHash: String?
    var raceResults: [LobbyRaceResult]?

    /// Number of current participants
    var participantCount: Int = 0

    init(
        id: String,
        creatorId: String,
        raceDistance: Int,
        entryFee: String,
        payoutMode: PayoutMode,
        status: LobbyStatus = .waiting,
        maxParticipants: Int = 10,
        minParticipants: Int = 2,
        skillRange: SkillRange? = nil,
        createdAt: Date = Date(),
        participantCount: Int = 0,
        raceResults: [LobbyRaceResult]? = nil
    ) {
        self.id = id
        self.creatorId = creatorId
        self.raceDistance = raceDistance
        self.entryFee = entryFee
        self.payoutMode = payoutMode
        self.status = status
        self.maxParticipants = maxParticipants
        self.minParticipants = minParticipants
        self.skillRange = skillRange
        self.createdAt = createdAt
        self.participantCount = participantCount
        self.raceResults = raceResults
    }

    var isCompleted: Bool {
        status == .completed
    }

    /// Race distance as enum
    var distance: RaceDistance? {
        RaceDistance(rawValue: raceDistance)
    }

    /// Entry fee in ETH (from wei)
    var entryFeeETH: Double {
        guard let wei = Double(entryFee) else { return 0 }
        return wei / 1_000_000_000_000_000_000 // ETH has 18 decimals
    }

    /// Formatted entry fee string
    var formattedEntryFee: String {
        let eth = entryFeeETH
        if eth < 0.01 {
            return String(format: "%.4f ETH", eth)
        } else {
            return String(format: "%.3f ETH", eth)
        }
    }

    /// Whether the lobby can start
    var canStart: Bool {
        status == .waiting && participantCount >= minParticipants
    }

    /// Whether the lobby is full
    var isFull: Bool {
        participantCount >= maxParticipants
    }

    /// Total prize pool in ETH
    var totalPoolETH: Double {
        entryFeeETH * Double(participantCount)
    }

    /// Prize pool after platform fee
    var prizePoolETH: Double {
        PlatformFee.prizePool(from: totalPoolETH)
    }
}

/// Skill range for matchmaking
struct SkillRange: Codable {
    var min: Int
    var max: Int

    func contains(_ rating: Int) -> Bool {
        rating >= min && rating <= max
    }
}

/// A participant in a lobby
struct LobbyParticipant: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    var displayName: String
    var walletAddress: String
    var equipmentType: EquipmentType
    var depositTxHash: String?
    var status: ParticipantStatus
    var joinedAt: Date
    var finishedAt: Date?
    var finalDistance: Double?
    var finalTime: TimeInterval?
}

/// Status of a participant
enum ParticipantStatus: String, Codable {
    case deposited = "deposited"
    case ready = "ready"
    case racing = "racing"
    case finished = "finished"
    case disconnected = "disconnected"
}

/// Race result for a participant (stored on completed lobbies)
struct LobbyRaceResult: Codable, Identifiable {
    let oderId: String
    let displayName: String
    var walletAddress: String?
    var position: Int?
    var finishTime: Double? // milliseconds
    var distance: Double
    var pace: Double
    var watts: Int
    var isBot: Bool?
    var isFinished: Bool

    var id: String { oderId }

    var formattedFinishTime: String {
        guard let finishTimeMs = finishTime else {
            return "--:--.-"
        }
        let totalSeconds = finishTimeMs / 1000.0
        let minutes = Int(totalSeconds) / 60
        let seconds = totalSeconds.truncatingRemainder(dividingBy: 60)
        return String(format: "%d:%05.2f", minutes, seconds)
    }

    var formattedPace: String {
        if pace <= 0 { return "-:--/500m" }
        let minutes = Int(pace) / 60
        let seconds = Int(pace) % 60
        return String(format: "%d:%02d/500m", minutes, seconds)
    }
}

// MARK: - Entry Fee Presets (ETH)

enum EntryFeePreset: CaseIterable, Identifiable {
    case free    // 0 ETH (for testing)
    case eth001  // 0.001 ETH
    case eth005  // 0.005 ETH
    case eth01   // 0.01 ETH
    case eth025  // 0.025 ETH
    case eth05   // 0.05 ETH
    case eth1    // 0.1 ETH

    var id: String { displayName }

    /// Entry fee in ETH
    var ethAmount: Double {
        switch self {
        case .free: return 0.0
        case .eth001: return 0.001
        case .eth005: return 0.005
        case .eth01: return 0.01
        case .eth025: return 0.025
        case .eth05: return 0.05
        case .eth1: return 0.1
        }
    }

    /// Entry fee in wei (ETH has 18 decimals)
    var weiAmount: String {
        let wei = ethAmount * 1_000_000_000_000_000_000
        return String(format: "%.0f", wei)
    }

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .eth001: return "0.001 ETH"
        case .eth005: return "0.005 ETH"
        case .eth01: return "0.01 ETH"
        case .eth025: return "0.025 ETH"
        case .eth05: return "0.05 ETH"
        case .eth1: return "0.1 ETH"
        }
    }

    /// Approximate USD value (for display only, actual price varies)
    var approximateUSD: String {
        if ethAmount == 0 {
            return "For testing"
        }
        // Assuming ~$2000/ETH for display purposes
        let usd = ethAmount * 2000
        if usd < 10 {
            return String(format: "~$%.2f", usd)
        } else {
            return String(format: "~$%.0f", usd)
        }
    }
}

// MARK: - Platform Fee

struct PlatformFee {
    /// Platform fee percentage (5%)
    static let percentage: Double = 0.05

    /// Calculate platform fee from total pool
    static func calculate(from totalPool: Double) -> Double {
        totalPool * percentage
    }

    /// Calculate prize pool after platform fee
    static func prizePool(from totalPool: Double) -> Double {
        totalPool * (1 - percentage)
    }
}
