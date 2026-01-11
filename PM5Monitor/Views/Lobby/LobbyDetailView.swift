import SwiftUI

struct LobbyDetailView: View {
    let lobby: Lobby
    @ObservedObject var lobbyService: LobbyService
    @ObservedObject var authService: AuthService
    @StateObject private var walletService = WalletService()

    @State private var isJoining = false
    @State private var hasJoined = false
    @State private var isReady = false
    @State private var isStartingRace = false
    @State private var showWalletRequired = false
    @State private var showInsufficientBalance = false
    @State private var showAddBot = false
    @State private var selectedEquipment: EquipmentType = .rower

    private var isCreator: Bool {
        authService.currentUser?.id == lobby.creatorId
    }

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

                // Add Bot section (for creator or when in lobby)
                if hasJoined && lobbyService.participants.count < lobby.maxParticipants {
                    AddBotCard(onAddBot: { difficulty in
                        addBot(difficulty: difficulty)
                    })
                }

                // Equipment selection (when not joined)
                if !hasJoined {
                    EquipmentSelectionCard(selectedEquipment: $selectedEquipment)
                }

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
        .alert("Insufficient Balance", isPresented: $showInsufficientBalance) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You need at least \(lobby.formattedEntryFee) + gas to join this race. Current balance: \(walletService.formattedETHBalance)")
        }
        .onAppear {
            lobbyService.subscribeToParticipants(lobbyId: lobby.id)
        }
        .onDisappear {
            if !hasJoined {
                lobbyService.unsubscribe()
            }
        }
        .onReceive(lobbyService.$participants) { participants in
            checkAndStartRace(participants: participants)
        }
    }

    private func checkAndStartRace(participants: [LobbyParticipant]) {
        print("checkAndStartRace called - participants: \(participants.count)")

        // Prevent multiple start attempts
        guard !isStartingRace else {
            print("  - Already starting race, skipping")
            return
        }

        // Only proceed if we're in the lobby and ready
        guard hasJoined, isReady else {
            print("  - Not joined (\(hasJoined)) or not ready (\(isReady))")
            return
        }

        // Need at least minParticipants
        guard participants.count >= lobby.minParticipants else {
            print("  - Not enough participants: \(participants.count) < \(lobby.minParticipants)")
            return
        }

        // Use server data to check if all are ready (bots count as ready)
        guard let serverLobby = NetworkService.shared.currentLobby else {
            print("  - No server lobby data")
            return
        }

        print("  - Server lobby participants:")
        for p in serverLobby.participants {
            print("    - \(p.displayName): status=\(p.status), isBot=\(p.isBot ?? false)")
        }

        let allReady = serverLobby.participants.allSatisfy { p in
            p.status == "ready" || p.isBot == true
        }

        print("  - All ready: \(allReady)")

        if allReady {
            print("  - Starting race!")
            isStartingRace = true
            startRace()
        }
    }

    private func startRace() {
        Task {
            do {
                _ = try await lobbyService.startRace()
            } catch {
                print("Failed to start race: \(error)")
                await MainActor.run {
                    isStartingRace = false
                }
            }
        }
    }

    private func joinLobby() {
        guard let userId = authService.currentUser?.id,
              let profile = authService.userProfile else { return }

        // Check wallet is connected
        guard walletService.isConnected,
              let walletAddress = walletService.walletAddress else {
            showWalletRequired = true
            return
        }

        // Check sufficient balance
        guard walletService.hasEnoughBalance(entryFeeWei: lobby.entryFee) else {
            showInsufficientBalance = true
            return
        }

        isJoining = true
        Task {
            do {
                // First, deposit to escrow
                // let txHash = try await walletService.depositToEscrow(
                //     lobbyId: lobby.id,
                //     entryFeeWei: lobby.entryFee
                // )

                // Then join the lobby
                try await lobbyService.joinLobby(
                    lobby.id,
                    userId: userId,
                    displayName: profile.displayName,
                    walletAddress: walletAddress,
                    equipmentType: selectedEquipment
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

            // Wait a moment for server to process and send lobbyUpdated
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            // Check if we can start the race now
            await MainActor.run {
                checkAndStartRace(participants: lobbyService.participants)
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

    private func addBot(difficulty: BotDifficulty) {
        Task {
            try? await lobbyService.addBot(difficulty: difficulty)
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
                    HStack(spacing: 12) {
                        // Equipment icon
                        Image(systemName: participant.equipmentType.iconName)
                            .font(.title2)
                            .foregroundColor(equipmentColor(for: participant.equipmentType))
                            .frame(width: 36)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(participant.displayName)
                                .font(.subheadline.weight(.medium))

                            Text(participant.equipmentType.displayName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        StatusBadge(status: participant.status)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private func equipmentColor(for type: EquipmentType) -> Color {
        switch type {
        case .rower: return .cyan
        case .bike: return .orange
        case .ski: return .purple
        }
    }
}

// MARK: - Equipment Selection Card

struct EquipmentSelectionCard: View {
    @Binding var selectedEquipment: EquipmentType

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Your Equipment")
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 12) {
                ForEach(EquipmentType.allCases) { equipment in
                    EquipmentOptionButton(
                        equipment: equipment,
                        isSelected: selectedEquipment == equipment,
                        action: { selectedEquipment = equipment }
                    )
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
}

struct EquipmentOptionButton: View {
    let equipment: EquipmentType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: equipment.iconName)
                    .font(.title)
                    .foregroundColor(isSelected ? equipmentColor : .gray)

                Text(equipment.shortName)
                    .font(.caption.weight(.medium))
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isSelected ? equipmentColor.opacity(0.2) : Color(.tertiarySystemGroupedBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? equipmentColor : Color.clear, lineWidth: 2)
            )
        }
    }

    private var equipmentColor: Color {
        switch equipment {
        case .rower: return .cyan
        case .bike: return .orange
        case .ski: return .purple
        }
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

// MARK: - Add Bot Card

struct AddBotCard: View {
    let onAddBot: (BotDifficulty) -> Void
    @State private var selectedDifficulty: BotDifficulty = .medium

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Add Bot")
                    .font(.headline)
                Spacer()
            }

            // Difficulty selection
            ForEach(BotDifficulty.allCases) { difficulty in
                Button {
                    onAddBot(difficulty)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(difficulty.displayName)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.primary)
                            Text(difficulty.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.cyan)
                    }
                    .padding()
                    .background(Color(.tertiarySystemGroupedBackground))
                    .cornerRadius(12)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
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
