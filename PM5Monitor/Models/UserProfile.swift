import Foundation

/// User profile for racing
struct UserProfile: Codable, Identifiable {
    let id: String
    var email: String?
    var displayName: String
    var walletAddress: String?

    /// ELO-based skill rating (default 1500)
    var skillRating: Int

    /// Total races participated
    var totalRaces: Int

    /// Total races won
    var totalWins: Int

    /// Total earnings in wei (stored as string for precision)
    var totalEarnings: String

    var createdAt: Date
    var lastActive: Date

    init(
        id: String,
        email: String? = nil,
        displayName: String,
        walletAddress: String? = nil,
        skillRating: Int = 1500,
        totalRaces: Int = 0,
        totalWins: Int = 0,
        totalEarnings: String = "0",
        createdAt: Date = Date(),
        lastActive: Date = Date()
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.walletAddress = walletAddress
        self.skillRating = skillRating
        self.totalRaces = totalRaces
        self.totalWins = totalWins
        self.totalEarnings = totalEarnings
        self.createdAt = createdAt
        self.lastActive = lastActive
    }

    /// Win rate percentage
    var winRate: Double {
        guard totalRaces > 0 else { return 0 }
        return Double(totalWins) / Double(totalRaces) * 100
    }

    /// Whether wallet is connected
    var hasWallet: Bool {
        walletAddress != nil && !walletAddress!.isEmpty
    }

    /// Alias for id used by the server
    var oderId: String {
        id
    }

    /// Total earnings formatted as ETH
    var formattedEarnings: String {
        guard let wei = Double(totalEarnings) else { return "0 ETH" }
        let eth = wei / 1_000_000_000_000_000_000
        return String(format: "%.4f ETH", eth)
    }
}

// MARK: - Firestore Keys

extension UserProfile {
    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName
        case walletAddress
        case skillRating
        case totalRaces
        case totalWins
        case totalEarnings
        case createdAt
        case lastActive
    }
}
