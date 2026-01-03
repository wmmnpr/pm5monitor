import Foundation
import Combine
import UIKit

// MARK: - WalletConnect Setup Instructions
/*
 ============================================
 WALLETCONNECT SETUP - REQUIRED STEPS
 ============================================

 1. ADD SWIFT PACKAGES in Xcode:
    File > Add Package Dependencies...

    Add these packages:
    - https://github.com/reown-com/reown-swift (WalletConnect v2)
      Select: ReownAppKit

 2. GET YOUR PROJECT ID:
    - Go to https://cloud.reown.com (formerly cloud.walletconnect.com)
    - Create a project
    - Copy your Project ID
    - Paste it in the `projectId` constant below

 3. CONFIGURE URL SCHEME:
    In Info.plist, add URL scheme for deep linking:
    - URL Types > Add new
    - URL Schemes: pm5racing

 4. ESCROW CONTRACT:
    - Deploy RaceEscrow.sol to your chosen network
    - Update `escrowContractAddress` below

 ============================================
 */

// Uncomment after adding packages:
// import ReownAppKit
// import ReownWalletKit

@MainActor
class WalletService: ObservableObject {

    // MARK: - Configuration

    /// WalletConnect Project ID - Get from https://cloud.reown.com
    private let projectId = "YOUR_PROJECT_ID_HERE"

    /// Ethereum RPC URL (Mainnet or Sepolia testnet)
    private let rpcUrl = "https://eth-mainnet.g.alchemy.com/v2/YOUR_API_KEY"
    // For testnet: "https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY"

    /// Race Escrow Contract Address
    private let escrowContractAddress = "0x0000000000000000000000000000000000000000"

    /// Chain ID (1 = Mainnet, 11155111 = Sepolia)
    private let chainId = 11155111 // Sepolia testnet for development

    // MARK: - Published State

    @Published var isConnected = false
    @Published var walletAddress: String?
    @Published var ethBalance: Double = 0
    @Published var isLoading = false
    @Published var error: WalletError?
    @Published var connectionURI: String?

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties

    var truncatedAddress: String {
        guard let address = walletAddress, address.count > 10 else {
            return walletAddress ?? ""
        }
        let start = address.prefix(6)
        let end = address.suffix(4)
        return "\(start)...\(end)"
    }

    var formattedETHBalance: String {
        if ethBalance < 0.0001 {
            return String(format: "%.6f ETH", ethBalance)
        } else if ethBalance < 1 {
            return String(format: "%.4f ETH", ethBalance)
        } else {
            return String(format: "%.3f ETH", ethBalance)
        }
    }

    // MARK: - Initialization

    init() {
        // Load saved wallet address
        if let savedAddress = UserDefaults.standard.string(forKey: "walletAddress") {
            walletAddress = savedAddress
            isConnected = true
            Task {
                try? await refreshBalance()
            }
        }
    }

    // MARK: - WalletConnect Connection

    /// Connect wallet using WalletConnect
    /// This generates a URI that the user scans with their wallet app
    func connect() async throws {
        isLoading = true
        error = nil

        defer { isLoading = false }

        // WalletConnect implementation:
        /*
        // Configure metadata
        let metadata = AppMetadata(
            name: "PM5 Racing",
            description: "Race on your Concept2 ergometer and win ETH",
            url: "https://pm5racing.app",
            icons: ["https://pm5racing.app/icon.png"],
            redirect: try! AppMetadata.Redirect(
                native: "pm5racing://",
                universal: nil,
                linkMode: false
            )
        )

        // Configure networking
        Networking.configure(
            groupIdentifier: "group.com.pm5racing",
            projectId: projectId,
            socketFactory: DefaultSocketFactory()
        )

        // Configure AppKit
        try await AppKit.configure(
            projectId: projectId,
            metadata: metadata
        )

        // Present the connection modal
        AppKit.present()

        // Listen for session
        AppKit.instance.sessionSettlePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] session in
                guard let self = self else { return }
                if let account = session.accounts.first {
                    self.walletAddress = account.address
                    self.isConnected = true
                    self.saveWalletAddress(account.address)
                    Task {
                        try? await self.refreshBalance()
                    }
                }
            }
            .store(in: &cancellables)
        */

        throw WalletError.notImplemented
    }

    /// Set wallet address manually (for testing or manual entry)
    func setWalletAddress(_ address: String) {
        guard isValidEthereumAddress(address) else {
            error = .invalidAddress
            return
        }
        walletAddress = address
        isConnected = true
        saveWalletAddress(address)

        Task {
            try? await refreshBalance()
        }
    }

    /// Disconnect wallet
    func disconnect() {
        // AppKit.instance.disconnect()
        walletAddress = nil
        isConnected = false
        ethBalance = 0
        UserDefaults.standard.removeObject(forKey: "walletAddress")
    }

    // MARK: - Balance

    /// Fetch ETH balance from the blockchain
    func refreshBalance() async throws {
        guard let address = walletAddress else {
            throw WalletError.notConnected
        }

        // JSON-RPC call to get balance
        let balance = try await fetchETHBalance(address: address)
        await MainActor.run {
            self.ethBalance = balance
        }
    }

    /// Check if wallet has sufficient balance for entry fee
    func hasEnoughBalance(entryFeeWei: String) -> Bool {
        guard let entryFee = Double(entryFeeWei) else { return false }
        let entryFeeETH = entryFee / 1_000_000_000_000_000_000
        // Add 10% buffer for gas
        return ethBalance >= (entryFeeETH * 1.1)
    }

    // MARK: - Escrow Transactions

    /// Deposit ETH to escrow for race entry
    /// Returns the transaction hash
    func depositToEscrow(lobbyId: String, entryFeeWei: String) async throws -> String {
        guard walletAddress != nil else {
            throw WalletError.notConnected
        }

        guard let entryFee = Double(entryFeeWei) else {
            throw WalletError.transactionFailed
        }

        let entryFeeETH = entryFee / 1_000_000_000_000_000_000
        guard ethBalance >= entryFeeETH else {
            throw WalletError.insufficientBalance
        }

        isLoading = true
        defer { isLoading = false }

        // Build the deposit transaction
        // The escrow contract's deposit function: deposit(bytes32 lobbyId)
        let lobbyIdBytes = lobbyId.data(using: .utf8)!.sha256Hex
        _ = buildDepositCallData(lobbyIdBytes: lobbyIdBytes)

        // Request signature via WalletConnect
        /*
        let tx = Ethereum.Transaction(
            from: walletAddress!,
            to: escrowContractAddress,
            value: entryFeeWei,
            data: txData,
            chainId: chainId
        )

        let result = try await AppKit.instance.request(.eth_sendTransaction(tx))
        let txHash = result as? String ?? ""

        // Wait for confirmation
        try await waitForConfirmation(txHash: txHash)

        // Refresh balance
        try await refreshBalance()

        return txHash
        */

        // Placeholder for testing
        throw WalletError.notImplemented
    }

    // MARK: - Private Helpers

    private func saveWalletAddress(_ address: String) {
        UserDefaults.standard.set(address, forKey: "walletAddress")
    }

    private func isValidEthereumAddress(_ address: String) -> Bool {
        guard address.hasPrefix("0x"), address.count == 42 else { return false }
        let hexPart = String(address.dropFirst(2))
        return hexPart.allSatisfy { $0.isHexDigit }
    }

    /// Fetch ETH balance using JSON-RPC
    private func fetchETHBalance(address: String) async throws -> Double {
        let requestBody: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_getBalance",
            "params": [address, "latest"],
            "id": 1
        ]

        guard let url = URL(string: rpcUrl) else {
            throw WalletError.connectionFailed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw WalletError.connectionFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resultHex = json["result"] as? String else {
            throw WalletError.connectionFailed
        }

        // Convert hex wei to ETH
        let weiString = String(resultHex.dropFirst(2)) // Remove "0x"
        guard let wei = UInt64(weiString, radix: 16) else {
            return 0
        }

        return Double(wei) / 1_000_000_000_000_000_000
    }

    /// Build calldata for deposit function
    private func buildDepositCallData(lobbyIdBytes: String) -> String {
        // deposit(bytes32 lobbyId)
        // Function selector: keccak256("deposit(bytes32)")[:4] = 0xb6b55f25 (example)
        let functionSelector = "0xb6b55f25"
        return functionSelector + lobbyIdBytes.padding(toLength: 64, withPad: "0", startingAt: 0)
    }
}

// MARK: - Data Extension for SHA256

extension Data {
    var sha256Hex: String {
        // Simple hash for lobby ID - in production use CryptoKit
        var result = ""
        for byte in self {
            result += String(format: "%02x", byte)
        }
        // Pad or truncate to 32 bytes (64 hex chars)
        if result.count < 64 {
            result = String(repeating: "0", count: 64 - result.count) + result
        } else if result.count > 64 {
            result = String(result.prefix(64))
        }
        return result
    }
}

// MARK: - Wallet Error

enum WalletError: LocalizedError {
    case notConnected
    case notImplemented
    case connectionFailed
    case transactionFailed
    case insufficientBalance
    case userRejected
    case invalidAddress
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Wallet is not connected"
        case .notImplemented:
            return "WalletConnect SDK not configured. Add the package and your Project ID."
        case .connectionFailed:
            return "Failed to connect to wallet"
        case .transactionFailed:
            return "Transaction failed"
        case .insufficientBalance:
            return "Insufficient ETH balance for entry fee + gas"
        case .userRejected:
            return "Transaction was rejected"
        case .invalidAddress:
            return "Invalid Ethereum address format"
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}
