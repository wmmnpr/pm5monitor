import Foundation

// MARK: - Equipment Type

/// The type of Concept2 ergometer being used
enum EquipmentType: String, Codable, CaseIterable, Identifiable {
    case rower = "rower"
    case bike = "bike"
    case ski = "ski"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rower: return "RowErg"
        case .bike: return "BikeErg"
        case .ski: return "SkiErg"
        }
    }

    var shortName: String {
        switch self {
        case .rower: return "Row"
        case .bike: return "Bike"
        case .ski: return "Ski"
        }
    }

    /// SF Symbol icon for this equipment
    var iconName: String {
        switch self {
        case .rower: return "figure.rowing"
        case .bike: return "figure.outdoor.cycle"
        case .ski: return "figure.skiing.crosscountry"
        }
    }

    /// Color associated with this equipment
    var color: String {
        switch self {
        case .rower: return "cyan"
        case .bike: return "orange"
        case .ski: return "purple"
        }
    }
}

/// Real-time metrics from a PM5 ergometer (row, bike, or ski)
struct RowingMetrics: Equatable {
    /// Elapsed time in seconds
    var elapsedTime: TimeInterval = 0

    /// Distance rowed in meters
    var distance: Double = 0

    /// Split time per 500m in seconds (pace)
    var pace: TimeInterval = 0

    /// Strokes per minute
    var strokeRate: Int = 0

    /// Total stroke count
    var strokeCount: Int = 0

    /// Current power output in watts
    var watts: Int = 0

    /// Average power output in watts
    var avgWatts: Int = 0

    /// Calories burned
    var calories: Int = 0

    /// Peak drive force in lbs
    var peakForce: Double = 0

    /// Average drive force in lbs
    var avgForce: Double = 0

    /// Drag factor (machine resistance)
    var dragFactor: Int = 0

    /// When this metrics snapshot was captured
    var timestamp: Date = Date()

    /// Progress percentage toward a target distance (0.0 - 1.0)
    func progress(toward targetDistance: Double) -> Double {
        guard targetDistance > 0 else { return 0 }
        return min(distance / targetDistance, 1.0)
    }

    /// Formatted pace string (e.g., "2:05.3")
    var formattedPace: String {
        guard pace > 0 else { return "--:--.-" }
        let minutes = Int(pace) / 60
        let seconds = pace.truncatingRemainder(dividingBy: 60)
        return String(format: "%d:%04.1f", minutes, seconds)
    }

    /// Formatted elapsed time string (e.g., "5:23")
    var formattedElapsedTime: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Formatted distance string (e.g., "2,543 m")
    var formattedDistance: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return "\(formatter.string(from: NSNumber(value: distance)) ?? "0") m"
    }
}

// MARK: - Race Distance Presets

enum RaceDistance: Int, CaseIterable, Identifiable {
    case m350 = 350
    case m500 = 500
    case oneK = 1000
    case twoK = 2000
    case fiveK = 5000
    case tenK = 10000

    var id: Int { rawValue }

    var meters: Double { Double(rawValue) }

    var displayName: String {
        switch self {
        case .m350: return "350m"
        case .m500: return "500m"
        case .oneK: return "1K"
        case .twoK: return "2K"
        case .fiveK: return "5K"
        case .tenK: return "10K"
        }
    }

    var fullName: String {
        switch self {
        case .m350: return "350 meters"
        case .m500: return "500 meters"
        case .oneK: return "1,000 meters"
        case .twoK: return "2,000 meters"
        case .fiveK: return "5,000 meters"
        case .tenK: return "10,000 meters"
        }
    }

    /// Estimated duration for display purposes
    var estimatedDuration: String {
        switch self {
        case .m350: return "~1 min"
        case .m500: return "~1.5 min"
        case .oneK: return "~3 min"
        case .twoK: return "~7 min"
        case .fiveK: return "~18 min"
        case .tenK: return "~40 min"
        }
    }

    /// Create from meters value
    static func fromMeters(_ meters: Int) -> RaceDistance {
        RaceDistance(rawValue: meters) ?? .twoK
    }
}
