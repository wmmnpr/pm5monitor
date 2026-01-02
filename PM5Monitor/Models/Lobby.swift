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
struct Lobby: Codable, Identifiable {
    let id: String
    let creatorId: String
    var raceDistance: Int // meters (5000, 10000)
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
        participantCount: Int = 0
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
    }

    /// Race distance as enum
    var distance: RaceDistance? {
        RaceDistance(rawValue: raceDistance)
    }

    /// Entry fee in USDC (6 decimals)
    var entryFeeUSDC: Double {
        guard let wei = Double(entryFee) else { return 0 }
        return wei / 1_000_000 // USDC has 6 decimals
    }

    /// Whether the lobby can start
    var canStart: Bool {
        status == .waiting && participantCount >= minParticipants
    }

    /// Whether the lobby is full
    var isFull: Bool {
        participantCount >= maxParticipants
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
struct LobbyParticipant: Codable, Identifiable {
    let id: String
    let oderId: String
    var displayName: String
    var walletAddress: String
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

// MARK: - Entry Fee Presets

enum EntryFeePreset: CaseIterable {
    case one
    case five
    case ten
    case twentyFive
    case fifty
    case hundred

    var usdcAmount: Double {
        switch self {
        case .one: return 1
        case .five: return 5
        case .ten: return 10
        case .twentyFive: return 25
        case .fifty: return 50
        case .hundred: return 100
        }
    }

    /// Entry fee in wei (USDC has 6 decimals)
    var weiAmount: String {
        String(Int(usdcAmount * 1_000_000))
    }

    var displayName: String {
        "$\(Int(usdcAmount)) USDC"
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
