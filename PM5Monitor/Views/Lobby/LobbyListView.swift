import SwiftUI

struct LobbyListView: View {
    @ObservedObject var lobbyService: LobbyService
    @ObservedObject var raceService: RaceService
    @ObservedObject var authService: AuthService
    @Binding var deepLinkLobby: Lobby?

    @State private var showCreateLobby = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
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
            .navigationDestination(isPresented: Binding(
                get: { deepLinkLobby != nil },
                set: { if !$0 { deepLinkLobby = nil } }
            )) {
                if let lobby = deepLinkLobby {
                    LobbyDetailView(
                        lobby: lobby,
                        lobbyService: lobbyService,
                        authService: authService,
                        networkService: NetworkService.shared
                    )
                }
            }
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
        authService: AuthService(),
        deepLinkLobby: .constant(nil)
    )
}
