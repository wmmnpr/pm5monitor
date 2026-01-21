import SwiftUI

struct LobbyDetailView: View {
    let lobby: Lobby
    @ObservedObject var lobbyService: LobbyService
    @ObservedObject var authService: AuthService
    @ObservedObject var networkService: NetworkService
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

                // Participants list / Race results
                ParticipantsCard(
                    participants: lobbyService.participants,
                    maxParticipants: lobby.maxParticipants,
                    lobby: lobby
                )

                // Add Bot section (for creator or when in lobby, not for completed races)
                if !lobby.isCompleted && hasJoined && lobbyService.participants.count < lobby.maxParticipants {
                    AddBotCard(onAddBot: { difficulty in
                        addBot(difficulty: difficulty)
                    })
                }

                // Equipment selection (when not joined, not for completed races)
                if !lobby.isCompleted && !hasJoined {
                    EquipmentSelectionCard(selectedEquipment: $selectedEquipment)
                }

                // Action buttons (hide for completed races)
                if !lobby.isCompleted {
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
            p.status == "ready" || (p.isBot ?? false)
        }

        print("  - All ready: \(allReady)")

        if allReady {
            print("  - Starting race!")
            isStartingRace = true
            startRace()
        }
    }

    private func startRace() {
        print("startRace() called")
        Task {
            do {
                print("startRace: calling lobbyService.startRace()")
                let raceId = try await lobbyService.startRace()
                print("startRace: SUCCESS - raceId = \(raceId)")
            } catch {
                print("startRace: FAILED - \(error)")
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
    let lobby: Lobby

    private var isRaceCompleted: Bool {
        lobby.isCompleted
    }

    private var sortedRaceResults: [LobbyRaceResult] {
        guard let results = lobby.raceResults else { return [] }
        return results.sorted { p1, p2 in
            if let pos1 = p1.position, let pos2 = p2.position {
                return pos1 < pos2
            } else if p1.position != nil {
                return true
            } else if p2.position != nil {
                return false
            }
            return p1.distance > p2.distance
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(isRaceCompleted ? "Race Results" : "Participants")
                    .font(.headline)
                Spacer()
                if isRaceCompleted {
                    Text("Completed")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(8)
                } else {
                    Text("\(participants.count)/\(maxParticipants)")
                        .foregroundColor(.secondary)
                }
            }

            if isRaceCompleted && !sortedRaceResults.isEmpty {
                // Show race results
                ForEach(sortedRaceResults) { result in
                    LobbyRaceResultRow(result: result)
                }
            } else if participants.isEmpty {
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

// MARK: - Lobby Race Result Row

struct LobbyRaceResultRow: View {
    let result: LobbyRaceResult
    @State private var showTipSheet = false

    /// Whether this participant can receive tips (has valid wallet address)
    private var canReceiveTip: Bool {
        guard let walletAddress = result.walletAddress,
              !walletAddress.isEmpty,
              walletAddress.hasPrefix("0x") else {
            return false
        }
        return true
    }

    var body: some View {
        HStack(spacing: 12) {
            // Position badge
            ZStack {
                Circle()
                    .fill(positionColor.opacity(0.2))
                    .frame(width: 36, height: 36)
                Text(positionText)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(positionColor)
            }

            // Name and bot indicator
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(result.displayName)
                        .font(.subheadline.weight(.medium))
                    if result.isBot == true {
                        Text("BOT")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.cyan.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                Text(result.formattedPace)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Tip button (only for non-bots with wallet addresses)
            if canReceiveTip {
                Button {
                    showTipSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gift.fill")
                            .font(.caption)
                        Text("Tip")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundColor(.purple)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.purple.opacity(0.15))
                    .cornerRadius(8)
                }
            }

            // Finish time
            VStack(alignment: .trailing, spacing: 2) {
                Text(result.formattedFinishTime)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundColor(result.isFinished ? .primary : .secondary)
                Text("\(result.watts)W")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showTipSheet) {
            TipWinnerSheet(
                recipientName: result.displayName,
                walletAddress: result.walletAddress ?? ""
            )
        }
    }

    private var positionText: String {
        if let pos = result.position {
            return "\(pos)"
        }
        return "-"
    }

    private var positionColor: Color {
        switch result.position {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .orange
        default: return .secondary
        }
    }
}

// MARK: - Tip Winner Sheet

struct TipWinnerSheet: View {
    let recipientName: String
    let walletAddress: String
    @Environment(\.dismiss) private var dismiss
    @State private var tipAmount: String = "0.001"
    @State private var showNoWalletsAlert = false

    private let presetAmounts = ["0.001", "0.005", "0.01", "0.05"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "gift.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.purple)

                    Text("Tip \(recipientName)")
                        .font(.title2.weight(.bold))

                    Text("Send ETH to congratulate them!")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)

                // Wallet address
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recipient Address")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(walletAddress)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .cornerRadius(12)
                }
                .padding(.horizontal)

                // Amount selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tip Amount (ETH)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    // Preset amounts
                    HStack(spacing: 8) {
                        ForEach(presetAmounts, id: \.self) { amount in
                            Button {
                                tipAmount = amount
                            } label: {
                                Text("\(amount)")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(tipAmount == amount ? .white : .purple)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(tipAmount == amount ? Color.purple : Color.purple.opacity(0.15))
                                    .cornerRadius(10)
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Custom amount input
                    TextField("Custom amount", text: $tipAmount)
                        .keyboardType(.decimalPad)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color(.tertiarySystemGroupedBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                }

                Spacer()

                // Wallet buttons
                VStack(spacing: 12) {
                    Text("Open in Wallet")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Show available wallets
                    let installedWallets = WalletDeepLinkService.installedWallets()

                    if installedWallets.isEmpty {
                        // No wallets installed - show generic options
                        ForEach(WalletDeepLinkService.WalletApp.allCases) { wallet in
                            WalletButton(
                                wallet: wallet,
                                isInstalled: false,
                                action: {
                                    openWallet(wallet)
                                }
                            )
                        }
                    } else {
                        // Show installed wallets first
                        ForEach(installedWallets) { wallet in
                            WalletButton(
                                wallet: wallet,
                                isInstalled: true,
                                action: {
                                    openWallet(wallet)
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Send Tip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func openWallet(_ wallet: WalletDeepLinkService.WalletApp) {
        let amount = Double(tipAmount) ?? 0.001
        WalletDeepLinkService.openWalletToSend(
            wallet: wallet,
            toAddress: walletAddress,
            amount: amount
        )
    }
}

// MARK: - Wallet Button

struct WalletButton: View {
    let wallet: WalletDeepLinkService.WalletApp
    let isInstalled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: wallet.iconName)
                    .font(.title2)
                    .foregroundColor(isInstalled ? .purple : .gray)
                    .frame(width: 36)

                Text(wallet.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(isInstalled ? .primary : .secondary)

                Spacer()

                if isInstalled {
                    Image(systemName: "arrow.up.forward.app.fill")
                        .foregroundColor(.purple)
                } else {
                    Text("Not installed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
        .disabled(!isInstalled)
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
            authService: AuthService(),
            networkService: NetworkService.shared
        )
    }
}
