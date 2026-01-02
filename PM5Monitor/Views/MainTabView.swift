import SwiftUI

struct MainTabView: View {
    @StateObject private var authService = AuthService()
    @StateObject private var lobbyService = LobbyService()
    @StateObject private var raceService = RaceService()
    @StateObject private var bleManager = BLEManager()
    @StateObject private var cameraManager = CameraManager()

    @State private var selectedTab = 0

    var body: some View {
        Group {
            if authService.isAuthenticated {
                // Check if in active race
                if raceService.raceState.isRacing {
                    RaceView(
                        raceService: raceService,
                        bleManager: bleManager,
                        cameraManager: cameraManager
                    )
                } else {
                    TabView(selection: $selectedTab) {
                        // Home / Training
                        TrainingView(
                            bleManager: bleManager,
                            cameraManager: cameraManager
                        )
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

// MARK: - Training View (existing functionality)

struct TrainingView: View {
    @ObservedObject var bleManager: BLEManager
    @ObservedObject var cameraManager: CameraManager

    var body: some View {
        NavigationStack {
            ZStack {
                // Camera preview
                if cameraManager.isRunning {
                    CameraPreviewView(session: cameraManager.session)
                        .ignoresSafeArea()
                } else {
                    Color.black.ignoresSafeArea()
                }

                // Overlays
                VStack {
                    Spacer()

                    HStack(alignment: .bottom) {
                        // Force curve
                        ForceCurveView(forceData: bleManager.forceHistory)
                            .frame(width: 150, height: 100)

                        Spacer()

                        // Watts display
                        WattsOverlayView(watts: bleManager.currentWatts, isConnected: bleManager.isConnected)
                    }
                    .padding()
                }

                // Connection overlay
                if !bleManager.isConnected {
                    ConnectionOverlay(ble: bleManager)
                }

                // Metrics overlay when connected
                if bleManager.isConnected {
                    VStack {
                        MetricsBar(metrics: bleManager.currentMetrics)
                        Spacer()
                    }
                }
            }
            .navigationTitle("Training")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                cameraManager.startSession()
            }
            .onDisappear {
                cameraManager.stopSession()
            }
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

                // Stats section
                if let profile = authService.userProfile {
                    Section("Statistics") {
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
