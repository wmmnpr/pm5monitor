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
                        // Home / Training
                        TrainingView(bleManager: bleManager)
                            .tabItem {
                                Label("Train", systemImage: "figure.rowing")
                            }
                            .tag(0)

                        // Race Lobbies
                        LobbyListView(
                            lobbyService: lobbyService,
                            raceService: raceService,
                            authService: authService
                        )
                        .tabItem {
                            Label("Race", systemImage: "flag.checkered")
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
            .navigationTitle("Training")
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
