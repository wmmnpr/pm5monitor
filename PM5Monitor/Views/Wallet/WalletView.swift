import SwiftUI

struct WalletView: View {
    @ObservedObject var authService: AuthService
    @StateObject private var walletService = WalletService()

    @State private var showConnectSheet = false
    @State private var showDepositSheet = false
    @State private var showWithdrawSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if walletService.isConnected {
                        // Connected wallet view
                        ConnectedWalletCard(walletService: walletService)

                        // Balance card
                        BalanceCard(walletService: walletService)

                        // Action buttons
                        ActionButtonsCard(
                            onDeposit: { showDepositSheet = true },
                            onWithdraw: { showWithdrawSheet = true }
                        )

                        // Transaction history
                        TransactionHistoryCard()
                    } else {
                        // Connect wallet prompt
                        ConnectWalletPrompt(onConnect: { showConnectSheet = true })
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Wallet")
            .sheet(isPresented: $showConnectSheet) {
                ConnectWalletSheet(
                    walletService: walletService,
                    authService: authService,
                    isPresented: $showConnectSheet
                )
            }
            .sheet(isPresented: $showDepositSheet) {
                DepositSheet(walletService: walletService, isPresented: $showDepositSheet)
            }
            .sheet(isPresented: $showWithdrawSheet) {
                WithdrawSheet(walletService: walletService, isPresented: $showWithdrawSheet)
            }
        }
    }
}

// MARK: - Connect Wallet Prompt

struct ConnectWalletPrompt: View {
    let onConnect: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
                .frame(height: 40)

            Image(systemName: "wallet.pass")
                .font(.system(size: 60))
                .foregroundColor(.cyan)

            Text("Connect Your Wallet")
                .font(.title2.bold())

            Text("Link your Ethereum wallet to deposit ETH and participate in races")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: onConnect) {
                HStack {
                    Image(systemName: "link.circle.fill")
                    Text("Connect Wallet")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color.cyan)
                .cornerRadius(12)
            }
            .padding(.horizontal)

            Spacer()
        }
    }
}

// MARK: - Connected Wallet Card

struct ConnectedWalletCard: View {
    @ObservedObject var walletService: WalletService

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Wallet Connected")
                    .font(.headline)
                Spacer()
            }

            HStack {
                Image(systemName: "creditcard")
                    .foregroundColor(.secondary)

                Text(walletService.truncatedAddress)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    UIPasteboard.general.string = walletService.walletAddress
                } label: {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.cyan)
                }
            }

            Button {
                walletService.disconnect()
            } label: {
                Text("Disconnect")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
}

// MARK: - Balance Card

struct BalanceCard: View {
    @ObservedObject var walletService: WalletService
    @State private var isRefreshing = false

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Balance")
                    .font(.headline)
                Spacer()
                Button {
                    refreshBalance()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundColor(.cyan)
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                }
                .disabled(isRefreshing)
            }

            HStack(spacing: 24) {
                // ETH Balance
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)
                            .overlay(
                                Image(systemName: "diamond.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white)
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text("ETH")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(walletService.formattedETHBalance)
                                .font(.title2.bold())
                        }
                    }
                }

                Spacer()
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private func refreshBalance() {
        isRefreshing = true
        Task {
            try? await walletService.refreshBalance()
            await MainActor.run {
                isRefreshing = false
            }
        }
    }
}

// MARK: - Action Buttons Card

struct ActionButtonsCard: View {
    let onDeposit: () -> Void
    let onWithdraw: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onDeposit) {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title)
                    Text("Deposit")
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Color.green.opacity(0.2))
                .foregroundColor(.green)
                .cornerRadius(12)
            }

            Button(action: onWithdraw) {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                    Text("Withdraw")
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Color.orange.opacity(0.2))
                .foregroundColor(.orange)
                .cornerRadius(12)
            }
        }
    }
}

// MARK: - Transaction History Card

struct TransactionHistoryCard: View {
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Recent Activity")
                    .font(.headline)
                Spacer()
                Button("See All") {}
                    .font(.caption)
            }

            // Placeholder for transactions
            VStack(spacing: 12) {
                Text("No recent transactions")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
}

// MARK: - Connect Wallet Sheet

struct ConnectWalletSheet: View {
    @ObservedObject var walletService: WalletService
    @ObservedObject var authService: AuthService
    @Binding var isPresented: Bool

    @State private var walletAddressInput = ""
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                    .frame(height: 20)

                Image(systemName: "wallet.pass.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.cyan)

                Text("Enter Your Wallet Address")
                    .font(.title2.bold())

                Text("Paste your Ethereum wallet address below")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Manual wallet address entry
                VStack(alignment: .leading, spacing: 8) {
                    Text("Wallet Address")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("0x...", text: $walletAddressInput)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                }
                .padding(.horizontal)

                // Paste button
                Button {
                    if let clipboardString = UIPasteboard.general.string {
                        walletAddressInput = clipboardString
                    }
                } label: {
                    HStack {
                        Image(systemName: "doc.on.clipboard")
                        Text("Paste from Clipboard")
                    }
                    .font(.subheadline)
                    .foregroundColor(.cyan)
                }

                Spacer()

                // Connect button
                Button {
                    connectWithAddress()
                } label: {
                    Text("Connect Wallet")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(isValidAddress ? Color.cyan : Color.gray)
                        .cornerRadius(12)
                }
                .disabled(!isValidAddress)
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Connect Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private var isValidAddress: Bool {
        walletAddressInput.hasPrefix("0x") && walletAddressInput.count == 42
    }

    private func connectWithAddress() {
        walletService.setWalletAddress(walletAddressInput)

        if walletService.isConnected {
            Task {
                try? await authService.linkWallet(address: walletAddressInput)
            }
            isPresented = false
        } else if let error = walletService.error {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Deposit Sheet

struct DepositSheet: View {
    @ObservedObject var walletService: WalletService
    @Binding var isPresented: Bool

    @State private var amount: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Enter the amount of ETH to deposit for race entry fees")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Amount input
                HStack {
                    TextField("0.00", text: $amount)
                        .font(.system(size: 48, weight: .bold))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)

                    Text("ETH")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .padding()

                // Quick amounts
                HStack(spacing: 12) {
                    QuickAmountButton(amount: "0.01", selectedAmount: $amount)
                    QuickAmountButton(amount: "0.025", selectedAmount: $amount)
                    QuickAmountButton(amount: "0.05", selectedAmount: $amount)
                    QuickAmountButton(amount: "0.1", selectedAmount: $amount)
                }

                Spacer()

                Button {
                    // Deposit action
                    isPresented = false
                } label: {
                    Text("Deposit")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(amount.isEmpty ? Color.gray : Color.green)
                        .cornerRadius(12)
                }
                .disabled(amount.isEmpty)
                .padding(.horizontal)
            }
            .padding()
            .navigationTitle("Deposit ETH")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

struct QuickAmountButton: View {
    let amount: String
    @Binding var selectedAmount: String

    var body: some View {
        Button {
            selectedAmount = amount
        } label: {
            Text("\(amount)")
                .font(.subheadline.weight(.medium))
                .foregroundColor(selectedAmount == amount ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(selectedAmount == amount ? Color.cyan : Color(.tertiarySystemGroupedBackground))
                .cornerRadius(20)
        }
    }
}

// MARK: - Withdraw Sheet

struct WithdrawSheet: View {
    @ObservedObject var walletService: WalletService
    @Binding var isPresented: Bool

    @State private var amount: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Enter the amount of ETH to withdraw to your wallet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Amount input
                HStack {
                    TextField("0.00", text: $amount)
                        .font(.system(size: 48, weight: .bold))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)

                    Text("ETH")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .padding()

                // Available balance
                HStack {
                    Text("Available:")
                    Text(walletService.formattedETHBalance)
                        .fontWeight(.semibold)
                    Button("Max") {
                        amount = String(format: "%.4f", walletService.ethBalance)
                    }
                    .font(.caption)
                    .foregroundColor(.cyan)
                }
                .font(.subheadline)
                .foregroundColor(.secondary)

                Spacer()

                Button {
                    // Withdraw action
                    isPresented = false
                } label: {
                    Text("Withdraw")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(amount.isEmpty ? Color.gray : Color.orange)
                        .cornerRadius(12)
                }
                .disabled(amount.isEmpty)
                .padding(.horizontal)
            }
            .padding()
            .navigationTitle("Withdraw ETH")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

#Preview {
    WalletView(authService: AuthService())
}
