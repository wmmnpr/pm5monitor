import Foundation

/// User profile for racing
struct UserProfile: Codable, Identifiable {
    let id: String
    var email: String?
    var displayName: String
    var walletAddress: String?

    // Concept2 Profile Data
    var concept2Id: Int?
    var lifetimeMeters: Int

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
        concept2Id: Int? = nil,
        lifetimeMeters: Int = 0,
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
        self.concept2Id = concept2Id
        self.lifetimeMeters = lifetimeMeters
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

    /// Formatted lifetime meters from Concept2
    var formattedLifetimeMeters: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0

        if lifetimeMeters >= 1_000_000 {
            let km = Double(lifetimeMeters) / 1000
            formatter.maximumFractionDigits = 1
            return "\(formatter.string(from: NSNumber(value: km / 1000)) ?? "0")M meters"
        } else if lifetimeMeters >= 1000 {
            let km = Double(lifetimeMeters) / 1000
            return "\(formatter.string(from: NSNumber(value: km)) ?? "0") km"
        } else {
            return "\(formatter.string(from: NSNumber(value: lifetimeMeters)) ?? "0") m"
        }
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
        case concept2Id
        case lifetimeMeters
        case skillRating
        case totalRaces
        case totalWins
        case totalEarnings
        case createdAt
        case lastActive
    }
}
