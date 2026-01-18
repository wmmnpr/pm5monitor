import SwiftUI

struct CreateLobbyView: View {
    @ObservedObject var lobbyService: LobbyService
    @ObservedObject var authService: AuthService
    @Binding var isPresented: Bool

    @State private var selectedDistance: RaceDistance = .twoK
    @State private var selectedEntryFee: EntryFeePreset = .free
    @State private var selectedPayoutMode: PayoutMode = .winnerTakesAll
    @State private var maxParticipants: Int = 2
    @State private var isCreating = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                // Distance section
                Section {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach(RaceDistance.allCases) { distance in
                            DistanceButton(
                                distance: distance,
                                isSelected: selectedDistance == distance
                            ) {
                                selectedDistance = distance
                            }
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Race Distance")
                } footer: {
                    Text("Estimated time: \(selectedDistance.estimatedDuration)")
                }

                // Entry fee section
                Section {
                    ForEach(EntryFeePreset.allCases) { fee in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fee.displayName)
                                    .font(.subheadline.weight(.medium))
                                Text(fee.approximateUSD)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if selectedEntryFee.ethAmount == fee.ethAmount {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.cyan)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedEntryFee = fee
                        }
                    }
                } header: {
                    Text("Entry Fee (ETH)")
                } footer: {
                    Text("Entry fee is paid in Ethereum. USD values are approximate.")
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
                                Image(systemName: "checkmark.circle.fill")
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
                    SummaryRow(title: "Max Pool", value: String(format: "%.3f ETH", selectedEntryFee.ethAmount * Double(maxParticipants)))
                    SummaryRow(title: "Max Prize (1st)", value: calculateMaxPrize())
                }
            }
            .navigationTitle("Create Race")
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
        let totalPool = selectedEntryFee.ethAmount * Double(maxParticipants)
        let prizePool = PlatformFee.prizePool(from: totalPool)

        switch selectedPayoutMode {
        case .winnerTakesAll:
            return String(format: "%.4f ETH", prizePool)
        case .topThree:
            let firstPlace = prizePool * 0.60
            return String(format: "%.4f ETH", firstPlace)
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

// MARK: - Distance Button

struct DistanceButton: View {
    let distance: RaceDistance
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(distance.displayName)
                    .font(.headline)
                Text(distance.estimatedDuration)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? Color.cyan : Color(.tertiarySystemGroupedBackground))
            .foregroundColor(isSelected ? .black : .primary)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
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
