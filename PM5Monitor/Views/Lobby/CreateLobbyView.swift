import SwiftUI

struct CreateLobbyView: View {
    @ObservedObject var lobbyService: LobbyService
    @ObservedObject var authService: AuthService
    @Binding var isPresented: Bool

    @State private var selectedDistance: RaceDistance = .fiveK
    @State private var selectedEntryFee: EntryFeePreset = .five
    @State private var selectedPayoutMode: PayoutMode = .winnerTakesAll
    @State private var maxParticipants: Int = 6
    @State private var isCreating = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                // Distance section
                Section("Race Distance") {
                    Picker("Distance", selection: $selectedDistance) {
                        ForEach(RaceDistance.allCases) { distance in
                            Text(distance.fullName).tag(distance)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Entry fee section
                Section("Entry Fee") {
                    ForEach([EntryFeePreset.one, .five, .ten, .twentyFive, .fifty], id: \.usdcAmount) { fee in
                        HStack {
                            Text(fee.displayName)
                            Spacer()
                            if selectedEntryFee.usdcAmount == fee.usdcAmount {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.cyan)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedEntryFee = fee
                        }
                    }
                }

                // Payout mode section
                Section {
                    ForEach(PayoutMode.allCases, id: \.self) { mode in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(mode.displayName)
                                    .font(.subheadline)
                                Text(mode.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if selectedPayoutMode == mode {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.cyan)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedPayoutMode = mode
                        }
                    }
                } header: {
                    Text("Payout Distribution")
                } footer: {
                    Text("Platform fee: 5% of total pool")
                }

                // Participants section
                Section("Max Participants") {
                    Stepper("\(maxParticipants) racers", value: $maxParticipants, in: 2...20)
                }

                // Summary section
                Section("Summary") {
                    SummaryRow(title: "Distance", value: selectedDistance.fullName)
                    SummaryRow(title: "Entry Fee", value: selectedEntryFee.displayName)
                    SummaryRow(title: "Max Pool", value: "$\(Int(selectedEntryFee.usdcAmount) * maxParticipants) USDC")
                    SummaryRow(title: "Max Prize", value: calculateMaxPrize())
                }
            }
            .navigationTitle("Create Lobby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        createLobby()
                    } label: {
                        if isCreating {
                            ProgressView()
                        } else {
                            Text("Create")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isCreating)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func calculateMaxPrize() -> String {
        let totalPool = selectedEntryFee.usdcAmount * Double(maxParticipants)
        let prizePool = PlatformFee.prizePool(from: totalPool)

        switch selectedPayoutMode {
        case .winnerTakesAll:
            return String(format: "$%.0f USDC", prizePool)
        case .topThree:
            let firstPlace = prizePool * 0.60
            return String(format: "$%.0f USDC (1st)", firstPlace)
        }
    }

    private func createLobby() {
        guard let creatorId = authService.currentUser?.id else {
            errorMessage = "You must be signed in"
            showError = true
            return
        }

        isCreating = true
        Task {
            do {
                _ = try await lobbyService.createLobby(
                    creatorId: creatorId,
                    distance: selectedDistance,
                    entryFee: selectedEntryFee,
                    payoutMode: selectedPayoutMode,
                    maxParticipants: maxParticipants
                )
                await MainActor.run {
                    isPresented = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isCreating = false
                }
            }
        }
    }
}

struct SummaryRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    CreateLobbyView(
        lobbyService: LobbyService(),
        authService: AuthService(),
        isPresented: .constant(true)
    )
}
