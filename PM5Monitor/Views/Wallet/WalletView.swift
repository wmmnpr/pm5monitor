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

            Text("Link your Ethereum wallet to deposit USDC and participate in races")
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

    var body: some View {
        VStack(spacing: 16) {
            Text("Balance")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 24) {
                // USDC Balance
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Text("$")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            )

                        VStack(alignment: .leading) {
                            Text("USDC")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(walletService.formattedUSDCBalance)
                                .font(.title2.bold())
                        }
                    }
                }

                Spacer()

                // ETH Balance (for gas)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("ETH (for gas)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(walletService.formattedETHBalance)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
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

    @State private var isConnecting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "wallet.pass.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.cyan)

                Text("Connect Your Wallet")
                    .font(.title2.bold())

                VStack(spacing: 16) {
                    // WalletConnect option
                    Button {
                        connectWallet()
                    } label: {
                        HStack {
                            Image(systemName: "link.circle")
                                .font(.title2)
                            VStack(alignment: .leading) {
                                Text("WalletConnect")
                                    .font(.headline)
                                Text("Connect any Ethereum wallet")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if isConnecting {
                                ProgressView()
                            } else {
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .disabled(isConnecting)
                }
                .padding(.horizontal)

                Spacer()

                Text("We support MetaMask, Rainbow, Trust Wallet, and other WalletConnect compatible wallets")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
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
        }
    }

    private func connectWallet() {
        isConnecting = true
        Task {
            do {
                try await walletService.connect()
                if let address = walletService.walletAddress {
                    try await authService.linkWallet(address: address)
                }
                await MainActor.run {
                    isPresented = false
                }
            } catch {
                await MainActor.run {
                    isConnecting = false
                }
            }
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
                Text("Enter the amount of USDC to deposit from your wallet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Amount input
                HStack {
                    Text("$")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)

                    TextField("0", text: $amount)
                        .font(.system(size: 48, weight: .bold))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)

                    Text("USDC")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .padding()

                // Quick amounts
                HStack(spacing: 12) {
                    QuickAmountButton(amount: "10", selectedAmount: $amount)
                    QuickAmountButton(amount: "25", selectedAmount: $amount)
                    QuickAmountButton(amount: "50", selectedAmount: $amount)
                    QuickAmountButton(amount: "100", selectedAmount: $amount)
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
            .navigationTitle("Deposit USDC")
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
            Text("$\(amount)")
                .font(.subheadline.weight(.medium))
                .foregroundColor(selectedAmount == amount ? .white : .primary)
                .padding(.horizontal, 16)
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
                Text("Enter the amount of USDC to withdraw to your wallet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Amount input
                HStack {
                    Text("$")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)

                    TextField("0", text: $amount)
                        .font(.system(size: 48, weight: .bold))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)

                    Text("USDC")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .padding()

                // Available balance
                HStack {
                    Text("Available:")
                    Text(walletService.formattedUSDCBalance)
                        .fontWeight(.semibold)
                    Button("Max") {
                        // Set max amount
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
            .navigationTitle("Withdraw USDC")
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
