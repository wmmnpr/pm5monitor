import SwiftUI

struct LobbyListView: View {
    @ObservedObject var lobbyService: LobbyService
    @ObservedObject var raceService: RaceService
    @ObservedObject var authService: AuthService

    @State private var showCreateLobby = false
    @State private var selectedDistance: RaceDistance = .fiveK

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Quick match section
                    QuickMatchSection(
                        selectedDistance: $selectedDistance,
                        lobbyService: lobbyService,
                        authService: authService
                    )

                    // Available lobbies
                    LobbiesSection(
                        lobbyService: lobbyService,
                        authService: authService,
                        networkService: NetworkService.shared
                    )
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Race")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateLobby = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showCreateLobby) {
                CreateLobbyView(
                    lobbyService: lobbyService,
                    authService: authService,
                    isPresented: $showCreateLobby
                )
            }
            .refreshable {
                try? await lobbyService.fetchAvailableLobbies()
            }
            .task {
                try? await lobbyService.fetchAvailableLobbies()
            }
        }
    }
}

// MARK: - Quick Match Section

struct QuickMatchSection: View {
    @Binding var selectedDistance: RaceDistance
    @ObservedObject var lobbyService: LobbyService
    @ObservedObject var authService: AuthService

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Match")
                .font(.headline)

            // Distance selector
            HStack(spacing: 12) {
                ForEach(RaceDistance.allCases) { distance in
                    DistanceButton(
                        distance: distance,
                        isSelected: selectedDistance == distance
                    ) {
                        selectedDistance = distance
                    }
                }
            }

            // Entry fee options
            VStack(spacing: 12) {
                QuickMatchRow(
                    entryFee: .eth005,
                    distance: selectedDistance,
                    lobbyService: lobbyService,
                    authService: authService
                )
                QuickMatchRow(
                    entryFee: .eth01,
                    distance: selectedDistance,
                    lobbyService: lobbyService,
                    authService: authService
                )
                QuickMatchRow(
                    entryFee: .eth025,
                    distance: selectedDistance,
                    lobbyService: lobbyService,
                    authService: authService
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
}

struct QuickMatchRow: View {
    let entryFee: EntryFeePreset
    let distance: RaceDistance
    @ObservedObject var lobbyService: LobbyService
    @ObservedObject var authService: AuthService

    @State private var isSearching = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entryFee.displayName)
                    .font(.headline)
                Text("Winner takes all")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                findMatch()
            } label: {
                if isSearching {
                    ProgressView()
                        .frame(width: 80)
                } else {
                    Text("Play")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(width: 80)
                        .padding(.vertical, 10)
                        .background(Color.green)
                        .cornerRadius(8)
                }
            }
            .disabled(isSearching)
        }
        .padding()
        .background(Color(.tertiarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private func findMatch() {
        guard let userId = authService.currentUser?.id,
              let skillRating = authService.userProfile?.skillRating else { return }

        isSearching = true
        Task {
            defer { isSearching = false }
            _ = try? await lobbyService.findMatch(
                userId: userId,
                distance: distance,
                entryFee: entryFee,
                skillRating: skillRating
            )
        }
    }
}

// MARK: - Lobbies Section

struct LobbiesSection: View {
    @ObservedObject var lobbyService: LobbyService
    @ObservedObject var authService: AuthService
    @ObservedObject var networkService: NetworkService

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Lobbies")
                    .font(.headline)
                Spacer()
                Text("\(lobbyService.availableLobbies.count) available")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if lobbyService.availableLobbies.isEmpty {
                EmptyLobbiesView()
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(lobbyService.availableLobbies) { lobby in
                        NavigationLink {
                            LobbyDetailView(
                                lobby: lobby,
                                lobbyService: lobbyService,
                                authService: authService,
                                networkService: networkService
                            )
                        } label: {
                            LobbyRow(lobby: lobby)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct EmptyLobbiesView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "flag.checkered.circle")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text("No open lobbies")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("Create one or use Quick Match")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
}

struct LobbyRow: View {
    let lobby: Lobby

    var body: some View {
        HStack {
            // Distance badge
            VStack {
                Text(lobby.distance?.displayName ?? "\(lobby.raceDistance)m")
                    .font(.headline)
                    .foregroundColor(.cyan)
            }
            .frame(width: 50)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(lobby.formattedEntryFee)
                        .font(.subheadline.weight(.semibold))

                    Text("•")
                        .foregroundColor(.secondary)

                    Text(lobby.payoutMode.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Image(systemName: "person.2")
                        .font(.caption)
                    Text("\(lobby.participantCount)/\(lobby.maxParticipants)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Status badge
            Text(lobby.isCompleted ? "Completed" : "Open")
                .font(.caption.weight(.medium))
                .foregroundColor(lobby.isCompleted ? .green : .orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(lobby.isCompleted ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                .cornerRadius(6)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

#Preview {
    LobbyListView(
        lobbyService: LobbyService(),
        raceService: RaceService(),
        authService: AuthService()
    )
}
