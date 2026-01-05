import SwiftUI

struct MainTabView: View {
    @StateObject private var authService = AuthService()
    @StateObject private var lobbyService = LobbyService()
    @StateObject private var raceService = RaceService()
    @StateObject private var bleManager = BLEManager()

    @State private var selectedTab = 0

    var body: some View {
        Group {
            if authService.isAuthenticated {
                // Check if in active race
                if raceService.raceState.isRacing {
                    RaceView(
                        raceService: raceService,
                        bleManager: bleManager
                    )
                } else {
                    TabView(selection: $selectedTab) {
                        // Race / Training
                        TrainingView(bleManager: bleManager, authService: authService)
                            .tabItem {
                                Label("Race", systemImage: "figure.rowing")
                            }
                            .tag(0)

                        // Lobby
                        LobbyListView(
                            lobbyService: lobbyService,
                            raceService: raceService,
                            authService: authService
                        )
                        .tabItem {
                            Label("Lobby", systemImage: "flag.checkered")
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
    }
}

// MARK: - Training View

struct TrainingView: View {
    @ObservedObject var bleManager: BLEManager
    @ObservedObject var authService: AuthService

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if bleManager.isConnected {
                    // Main training display
                    VStack(spacing: 0) {
                        // Top metrics bar
                        MetricsBar(metrics: bleManager.currentMetrics)
                            .padding(.top)

                        // Race lane visualization
                        TrainingLaneView(
                            displayName: authService.userProfile?.displayName ?? "You",
                            distance: bleManager.currentMetrics.distance,
                            targetDistance: 2000
                        )
                        .frame(height: 80)
                        .padding(.horizontal)
                        .padding(.top, 8)

                        Spacer()

                        // Center: Large watts display
                        VStack(spacing: 8) {
                            Text("\(bleManager.currentWatts)")
                                .font(.system(size: 120, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            Text("WATTS")
                                .font(.title3.weight(.semibold))
                                .foregroundColor(.gray)
                        }

                        Spacer()

                        // Bottom: Force curve and additional metrics
                        HStack(alignment: .bottom, spacing: 24) {
                            // Force curve
                            VStack(alignment: .leading, spacing: 4) {
                                Text("FORCE CURVE")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                ForceCurveView(forceData: bleManager.forceHistory)
                                    .frame(width: 160, height: 80)
                            }

                            Spacer()

                            // Additional metrics
                            VStack(alignment: .trailing, spacing: 12) {
                                MetricDisplay(title: "PACE", value: bleManager.currentMetrics.formattedPace, unit: "/500m")
                                MetricDisplay(title: "S/M", value: "\(bleManager.currentMetrics.strokeRate)", unit: "")
                            }
                        }
                        .padding()
                        .padding(.bottom, 20)
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

// MARK: - Training Lane View (ErgRace Style)

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
