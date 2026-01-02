import SwiftUI

struct LobbyDetailView: View {
    let lobby: Lobby
    @ObservedObject var lobbyService: LobbyService
    @ObservedObject var authService: AuthService

    @State private var isJoining = false
    @State private var hasJoined = false
    @State private var isReady = false
    @State private var showWalletRequired = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header card
                LobbyHeaderCard(lobby: lobby)

                // Prize pool info
                PrizePoolCard(lobby: lobby)

                // Participants list
                ParticipantsCard(
                    participants: lobbyService.participants,
                    maxParticipants: lobby.maxParticipants
                )

                // Action buttons
                ActionButtonsSection(
                    lobby: lobby,
                    hasJoined: hasJoined,
                    isReady: isReady,
                    isJoining: isJoining,
                    onJoin: joinLobby,
                    onReady: markReady,
                    onLeave: leaveLobby
                )
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Lobby")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Wallet Required", isPresented: $showWalletRequired) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please connect your wallet before joining a race")
        }
        .onAppear {
            lobbyService.subscribeToParticipants(lobbyId: lobby.id)
        }
        .onDisappear {
            if !hasJoined {
                lobbyService.unsubscribe()
            }
        }
    }

    private func joinLobby() {
        guard let userId = authService.currentUser?.id,
              let profile = authService.userProfile else { return }

        guard let walletAddress = profile.walletAddress, !walletAddress.isEmpty else {
            showWalletRequired = true
            return
        }

        isJoining = true
        Task {
            do {
                try await lobbyService.joinLobby(
                    lobby.id,
                    userId: userId,
                    displayName: profile.displayName,
                    walletAddress: walletAddress
                )
                await MainActor.run {
                    hasJoined = true
                    isJoining = false
                }
            } catch {
                await MainActor.run {
                    isJoining = false
                }
            }
        }
    }

    private func markReady() {
        guard let userId = authService.currentUser?.id else { return }

        Task {
            try? await lobbyService.setReady(userId: userId)
            await MainActor.run {
                isReady = true
            }
        }
    }

    private func leaveLobby() {
        Task {
            try? await lobbyService.leaveLobby()
            await MainActor.run {
                hasJoined = false
                isReady = false
            }
        }
    }
}

// MARK: - Lobby Header Card

struct LobbyHeaderCard: View {
    let lobby: Lobby

    var body: some View {
        VStack(spacing: 16) {
            // Distance
            Text(lobby.distance?.displayName ?? "\(lobby.raceDistance)m")
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(.cyan)

            Text(lobby.distance?.fullName ?? "Race")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Entry fee
            HStack(spacing: 8) {
                Image(systemName: "diamond.fill")
                    .foregroundColor(.purple)
                Text("\(lobby.formattedEntryFee) Entry")
                    .font(.headline)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.purple.opacity(0.2))
            .cornerRadius(20)

            // Payout mode
            Text(lobby.payoutMode.displayName)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
}

// MARK: - Prize Pool Card

struct PrizePoolCard: View {
    let lobby: Lobby

    private var totalPool: Double {
        lobby.entryFeeETH * Double(lobby.participantCount)
    }

    private var maxPool: Double {
        lobby.entryFeeETH * Double(lobby.maxParticipants)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Prize Pool")
                    .font(.headline)
                Spacer()
                Text("5% platform fee")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Current pool
            HStack {
                Text("Current Pool")
                Spacer()
                Text(String(format: "%.4f ETH", totalPool))
                    .fontWeight(.semibold)
            }

            // Potential pool
            HStack {
                Text("Max Pool (if full)")
                Spacer()
                Text(String(format: "%.4f ETH", maxPool))
                    .foregroundColor(.secondary)
            }

            Divider()

            // Prize distribution
            let payouts = PrizeDistribution.calculate(mode: lobby.payoutMode, totalPool: totalPool)
            ForEach(Array(payouts.enumerated()), id: \.offset) { index, payout in
                HStack {
                    Text(positionText(index))
                        .foregroundColor(positionColor(index))
                    Spacer()
                    Text(String(format: "%.4f ETH", payout))
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private func positionText(_ index: Int) -> String {
        switch index {
        case 0: return "1st Place"
        case 1: return "2nd Place"
        case 2: return "3rd Place"
        default: return "\(index + 1)th Place"
        }
    }

    private func positionColor(_ index: Int) -> Color {
        switch index {
        case 0: return .yellow
        case 1: return .gray
        case 2: return .orange
        default: return .secondary
        }
    }
}

// MARK: - Participants Card

struct ParticipantsCard: View {
    let participants: [LobbyParticipant]
    let maxParticipants: Int

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Participants")
                    .font(.headline)
                Spacer()
                Text("\(participants.count)/\(maxParticipants)")
                    .foregroundColor(.secondary)
            }

            if participants.isEmpty {
                Text("No participants yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(participants) { participant in
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.title2)
                            .foregroundColor(.cyan)

                        Text(participant.displayName)
                            .font(.subheadline)

                        Spacer()

                        StatusBadge(status: participant.status)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
}

struct StatusBadge: View {
    let status: ParticipantStatus

    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(8)
    }

    private var backgroundColor: Color {
        switch status {
        case .deposited: return .orange.opacity(0.2)
        case .ready: return .green.opacity(0.2)
        case .racing: return .blue.opacity(0.2)
        case .finished: return .purple.opacity(0.2)
        case .disconnected: return .red.opacity(0.2)
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .deposited: return .orange
        case .ready: return .green
        case .racing: return .blue
        case .finished: return .purple
        case .disconnected: return .red
        }
    }
}

// MARK: - Action Buttons

struct ActionButtonsSection: View {
    let lobby: Lobby
    let hasJoined: Bool
    let isReady: Bool
    let isJoining: Bool
    let onJoin: () -> Void
    let onReady: () -> Void
    let onLeave: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if !hasJoined {
                // Join button
                Button(action: onJoin) {
                    if isJoining {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                    } else {
                        Text("Join Lobby - \(lobby.formattedEntryFee)")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color.cyan)
                            .cornerRadius(12)
                    }
                }
                .disabled(isJoining || lobby.isFull)
            } else {
                if !isReady {
                    // Ready button
                    Button(action: onReady) {
                        Text("Ready!")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color.green)
                            .cornerRadius(12)
                    }

                    // Leave button
                    Button(action: onLeave) {
                        Text("Leave Lobby")
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }
                } else {
                    // Waiting for others
                    HStack {
                        ProgressView()
                        Text("Waiting for other players...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .cornerRadius(12)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        LobbyDetailView(
            lobby: Lobby(
                id: "preview",
                creatorId: "user-1",
                raceDistance: 5000,
                entryFee: "5000000",
                payoutMode: .topThree,
                participantCount: 3
            ),
            lobbyService: LobbyService(),
            authService: AuthService()
        )
    }
}
