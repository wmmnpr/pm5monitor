import SwiftUI

struct MainTabView: View {
    @StateObject private var authService = AuthService()
    @StateObject private var lobbyService = LobbyService()
    @StateObject private var raceService = RaceService()
    @StateObject private var bleManager = BLEManager()
    @ObservedObject private var networkService = NetworkService.shared

    @State private var selectedTab = 0

    var body: some View {
        Group {
            if authService.isAuthenticated {
                // Check if in active race (from server) - status can be "active" or "racing"
                if let currentRace = networkService.currentRace,
                   (currentRace.status == "active" || currentRace.status == "racing") {
                    RaceView(
                        raceService: raceService,
                        bleManager: bleManager,
                        networkService: networkService,
                        currentUserId: authService.userProfile?.oderId ?? ""
                    )
                } else if raceService.raceState.isRacing {
                    RaceView(
                        raceService: raceService,
                        bleManager: bleManager,
                        networkService: networkService,
                        currentUserId: authService.userProfile?.oderId ?? ""
                    )
                } else {
                    TabView(selection: $selectedTab) {
                        // Race / Training
                        TrainingView(bleManager: bleManager, authService: authService, networkService: networkService)
                            .tabItem {
                                Label("Race", systemImage: "flag.checkered")
                            }
                            .tag(0)

                        // Lobby
                        LobbyListView(
                            lobbyService: lobbyService,
                            raceService: raceService,
                            authService: authService
                        )
                        .tabItem {
                            Label("Lobby", systemImage: "person.3.fill")
                        }
                        .tag(1)

                        // Wallet
                        WalletView(authService: authService)
                            .tabItem {
                                Label("Wallet", systemImage: "wallet.pass")
                            }
                            .tag(2)

                        // Profile
                        ProfileView(authService: authService)
                            .tabItem {
                                Label("Profile", systemImage: "person.circle")
                            }
                            .tag(3)
                    }
                    .tint(.cyan)
                }
            } else {
                LoginView(authService: authService)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            setupNetworkCallbacks()
        }
    }

    // MARK: - Socket.IO Callback Setup

    private func setupNetworkCallbacks() {
        // Handle countdown events from Socket.IO
        networkService.onCountdown = { [weak raceService, weak bleManager, weak networkService] seconds in
            Task { @MainActor in
                // Configure PM5 and reset metrics when countdown starts (first countdown event)
                if raceService?.countdown == nil,
                   let targetDistance = networkService?.currentRace?.targetDistance {
                    // Reset metrics from previous race
                    bleManager?.resetMetrics()
                    // Configure PM5 with the race distance
                    bleManager?.configureWorkout(distance: targetDistance)
                }

                raceService?.countdown = seconds
                if case .inLobby = raceService?.raceState {
                    raceService?.raceState = .countdown(seconds: seconds)
                } else if case .countdown = raceService?.raceState {
                    raceService?.raceState = .countdown(seconds: seconds)
                }
            }
        }

        // Handle race started events from Socket.IO
        networkService.onRaceStarted = { [weak raceService] _ in
            Task { @MainActor in
                raceService?.raceState = .racing
            }
        }

        // Handle race completed events from Socket.IO
        networkService.onRaceCompleted = { [weak raceService] race in
            Task { @MainActor in
                // Find user's position from the race participants
                if let userId = authService.userProfile?.oderId,
                   let participant = race.participants.first(where: { $0.oderId == userId }),
                   let position = participant.position {
                    raceService?.raceState = .finished(position: position)
                } else {
                    // Default to position 0 if not found
                    raceService?.raceState = .finished(position: 0)
                }
            }
        }
    }
}

// MARK: - Training View

struct TrainingView: View {
    @ObservedObject var bleManager: BLEManager
    @ObservedObject var authService: AuthService
    @ObservedObject var networkService: NetworkService

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if bleManager.isConnected {
                    // Main training display
                    VStack(spacing: 0) {
                        Spacer()

                        // Race lane visualization - show multiple lanes if in a race
                        if let currentRace = networkService.currentRace {
                            MultiRacerLaneView(
                                participants: currentRace.participants,
                                currentUserId: authService.userProfile?.oderId ?? "",
                                currentUserDistance: bleManager.currentMetrics.distance,
                                targetDistance: Double(currentRace.targetDistance)
                            )
                            .frame(height: CGFloat(max(2, currentRace.participants.count)) * 60)
                            .padding(.horizontal)
                        } else {
                            TrainingLaneView(
                                displayName: authService.userProfile?.displayName ?? "You",
                                distance: bleManager.currentMetrics.distance,
                                targetDistance: 2000
                            )
                            .frame(height: 100)
                            .padding(.horizontal)
                        }

                        Spacer()
                    }
                } else {
                    // Connection overlay
                    ConnectionOverlay(ble: bleManager)
                }
            }
            .navigationTitle("Race")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if bleManager.isConnected {
                            bleManager.disconnect()
                        } else {
                            bleManager.startScanning()
                        }
                    } label: {
                        Image(systemName: bleManager.isConnected ? "link.circle.fill" : "link.circle")
                            .foregroundColor(bleManager.isConnected ? .green : .gray)
                    }
                }
            }
        }
    }
}

// MARK: - Metric Display

struct MetricDisplay: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.gray)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        }
    }
}

// MARK: - Metrics Bar

struct MetricsBar: View {
    let metrics: RowingMetrics

    var body: some View {
        HStack(spacing: 16) {
            MetricPill(title: "Distance", value: metrics.formattedDistance)
            MetricPill(title: "Pace", value: metrics.formattedPace)
            MetricPill(title: "S/M", value: "\(metrics.strokeRate)")
            MetricPill(title: "Time", value: metrics.formattedElapsedTime)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

struct MetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundColor(.primary)
        }
        .frame(minWidth: 60)
    }
}

// MARK: - Multi-Racer Lane View (ErgRace Style)

struct MultiRacerLaneView: View {
    let participants: [ServerRaceParticipant]
    let currentUserId: String
    let currentUserDistance: Double
    let targetDistance: Double

    private let laneColors: [Color] = [
        Color(red: 0.1, green: 0.3, blue: 0.5),
        Color(red: 0.15, green: 0.35, blue: 0.55),
    ]

    var body: some View {
        GeometryReader { geometry in
            let laneCount = max(2, participants.count)
            let laneHeight = geometry.size.height / CGFloat(laneCount)

            ZStack {
                // Lane backgrounds
                VStack(spacing: 0) {
                    ForEach(0..<laneCount, id: \.self) { index in
                        Rectangle()
                            .fill(laneColors[index % 2])
                            .frame(height: laneHeight)
                    }
                }

                // Distance markers
                ForEach(distanceMarkers, id: \.self) { marker in
                    let xPos = calculateXPosition(progress: marker / targetDistance, width: geometry.size.width)
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 1, height: geometry.size.height)
                        .position(x: xPos, y: geometry.size.height / 2)
                }

                // Lane dividers
                ForEach(1..<laneCount, id: \.self) { index in
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: geometry.size.width, height: 1)
                        .position(x: geometry.size.width / 2, y: CGFloat(index) * laneHeight)
                }

                // Start line
                Rectangle()
                    .fill(Color.green.opacity(0.8))
                    .frame(width: 3, height: geometry.size.height)
                    .position(x: 35, y: geometry.size.height / 2)

                // Finish line (checkered)
                HStack(spacing: 0) {
                    ForEach(0..<2, id: \.self) { col in
                        VStack(spacing: 0) {
                            ForEach(0..<(laneCount * 2), id: \.self) { row in
                                Rectangle()
                                    .fill((row + col) % 2 == 0 ? Color.white : Color.black)
                                    .frame(width: 6, height: laneHeight / 2)
                            }
                        }
                    }
                }
                .position(x: geometry.size.width - 18, y: geometry.size.height / 2)

                // All racers
                ForEach(Array(sortedParticipants.enumerated()), id: \.element.id) { index, participant in
                    let isMe = participant.oderId == currentUserId
                    let distance = isMe ? currentUserDistance : participant.distance
                    let pace = participant.pace
                    let progress = min(1.0, distance / targetDistance)
                    let xPosition = calculateXPosition(progress: progress, width: geometry.size.width)
                    let yPosition = (CGFloat(index) + 0.5) * laneHeight

                    RacerIconView(
                        displayName: participant.displayName,
                        equipmentType: participant.equipment,
                        isMe: isMe,
                        distance: distance,
                        pace: pace,
                        xPosition: xPosition,
                        yPosition: yPosition
                    )
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var sortedParticipants: [ServerRaceParticipant] {
        // Sort by distance (leader first), but keep current user visible
        participants.sorted { p1, p2 in
            let d1 = p1.oderId == currentUserId ? currentUserDistance : p1.distance
            let d2 = p2.oderId == currentUserId ? currentUserDistance : p2.distance
            return d1 > d2
        }
    }

    private var distanceMarkers: [Double] {
        let interval: Double = targetDistance <= 1000 ? 250 : 500
        var markers: [Double] = []
        var current = interval
        while current < targetDistance {
            markers.append(current)
            current += interval
        }
        return markers
    }

    private func calculateXPosition(progress: Double, width: CGFloat) -> CGFloat {
        let trackStart: CGFloat = 40
        let trackEnd = width - 25
        let trackLength = trackEnd - trackStart
        return trackStart + (trackLength * CGFloat(progress))
    }
}

struct RacerIconView: View {
    let displayName: String
    let equipmentType: EquipmentType
    let isMe: Bool
    let distance: Double
    let pace: Double
    let xPosition: CGFloat
    let yPosition: CGFloat

    private var equipmentColor: Color {
        switch equipmentType {
        case .rower: return .cyan
        case .bike: return .orange
        case .ski: return .purple
        }
    }

    private var formattedPace: String {
        guard pace > 0 else { return "-:--" }
        let minutes = Int(pace) / 60
        let seconds = Int(pace) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var formattedDistance: String {
        return "\(Int(distance))m"
    }

    var body: some View {
        VStack(spacing: 2) {
            // Racer icon and name
            HStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(isMe ? equipmentColor : Color.white.opacity(0.9))
                        .frame(width: 28, height: 28)

                    Image(systemName: equipmentType.iconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isMe ? .white : equipmentColor)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(isMe ? "YOU" : String(displayName.prefix(6)).uppercased())
                        .font(.system(size: 10, weight: isMe ? .bold : .medium))
                        .foregroundColor(.white)

                    HStack(spacing: 6) {
                        Text(formattedDistance)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.yellow)

                        Text(formattedPace)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.green)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(isMe ? equipmentColor.opacity(0.9) : Color.black.opacity(0.7))
                .cornerRadius(4)
            }
        }
        .position(x: xPosition, y: yPosition)
        .animation(.easeInOut(duration: 0.3), value: xPosition)
    }
}

// MARK: - Training Lane View (ErgRace Style - Solo)

struct TrainingLaneView: View {
    let displayName: String
    let distance: Double
    let targetDistance: Double

    private let laneColor = Color(red: 0.1, green: 0.3, blue: 0.5)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Lane background
                RoundedRectangle(cornerRadius: 8)
                    .fill(laneColor)

                // Distance markers
                ForEach(distanceMarkers, id: \.self) { marker in
                    let xPos = calculateXPosition(progress: marker / targetDistance, width: geometry.size.width)

                    VStack {
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 1, height: geometry.size.height)
                    }
                    .position(x: xPos, y: geometry.size.height / 2)
                }

                // Start line
                Rectangle()
                    .fill(Color.green.opacity(0.8))
                    .frame(width: 3, height: geometry.size.height)
                    .position(x: 35, y: geometry.size.height / 2)

                // Finish line (checkered)
                HStack(spacing: 0) {
                    ForEach(0..<2, id: \.self) { col in
                        VStack(spacing: 0) {
                            ForEach(0..<4, id: \.self) { row in
                                Rectangle()
                                    .fill((row + col) % 2 == 0 ? Color.white : Color.black)
                                    .frame(width: 6, height: geometry.size.height / 4)
                            }
                        }
                    }
                }
                .position(x: geometry.size.width - 18, y: geometry.size.height / 2)

                // User racer icon
                let progress = min(1.0, distance / targetDistance)
                let xPosition = calculateXPosition(progress: progress, width: geometry.size.width)

                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(Color.cyan)
                            .frame(width: 32, height: 32)

                        Image(systemName: "figure.rowing")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    Text(displayName.prefix(8).uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.cyan)
                        .cornerRadius(4)
                }
                .position(x: xPosition, y: geometry.size.height / 2)

                // Distance label
                Text("\(Int(distance))m / \(Int(targetDistance))m")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .position(x: geometry.size.width - 60, y: 12)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var distanceMarkers: [Double] {
        let interval: Double = targetDistance <= 1000 ? 250 : 500
        var markers: [Double] = []
        var current = interval
        while current < targetDistance {
            markers.append(current)
            current += interval
        }
        return markers
    }

    private func calculateXPosition(progress: Double, width: CGFloat) -> CGFloat {
        let trackStart: CGFloat = 40
        let trackEnd = width - 25
        let trackLength = trackEnd - trackStart
        return trackStart + (trackLength * CGFloat(progress))
    }
}

// MARK: - Profile View

struct ProfileView: View {
    @ObservedObject var authService: AuthService

    var body: some View {
        NavigationStack {
            List {
                // User info section
                Section {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.cyan)

                        VStack(alignment: .leading) {
                            Text(authService.userProfile?.displayName ?? "Guest")
                                .font(.headline)
                            if let email = authService.userProfile?.email {
                                Text(email)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                // Race Stats section
                if let profile = authService.userProfile {
                    Section("Race Statistics") {
                        StatRow(title: "Skill Rating", value: "\(profile.skillRating)")
                        StatRow(title: "Total Races", value: "\(profile.totalRaces)")
                        StatRow(title: "Wins", value: "\(profile.totalWins)")
                        StatRow(title: "Win Rate", value: String(format: "%.1f%%", profile.winRate))
                    }
                }

                // Settings section
                Section("Settings") {
                    NavigationLink {
                        Text("Notifications Settings")
                    } label: {
                        Label("Notifications", systemImage: "bell")
                    }

                    NavigationLink {
                        Text("Privacy Settings")
                    } label: {
                        Label("Privacy", systemImage: "lock")
                    }
                }

                // Sign out
                Section {
                    Button(role: .destructive) {
                        try? authService.signOut()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Profile")
        }
    }
}

struct StatRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    MainTabView()
}
