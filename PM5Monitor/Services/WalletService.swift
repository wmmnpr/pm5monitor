import Foundation
import Combine

// MARK: - Web3 Setup Instructions
/*
 ============================================
 WEB3 / WALLETCONNECT SETUP
 ============================================

 1. ADD WEB3 PACKAGES:
    In Xcode: File > Add Package Dependencies
    - https://github.com/WalletConnect/WalletConnectSwiftV2.git
    - https://github.com/attaswift/BigInt.git

 2. WALLETCONNECT PROJECT:
    - Go to https://cloud.walletconnect.com
    - Create a project
    - Get your Project ID
    - Add it to WalletService.projectId

 3. SMART CONTRACT:
    - Deploy RaceEscrow.sol to Ethereum (testnet first)
    - Update escrowContractAddress

 ============================================
 */

// Uncomment after adding Web3 packages:
// import WalletConnectSwift
// import Web3
// import BigInt

@MainActor
class WalletService: ObservableObject {

    // MARK: - Published State

    @Published var isConnected = false
    @Published var walletAddress: String?
    @Published var ethBalance: Double = 0   // In ETH (not wei)
    @Published var isLoading = false
    @Published var error: WalletError?

    // MARK: - Configuration

    // WalletConnect Project ID - Get from https://cloud.walletconnect.com
    private let projectId = "YOUR_WALLETCONNECT_PROJECT_ID"

    // Race Escrow Contract (deploy and update this)
    private let escrowContractAddress = "0x0000000000000000000000000000000000000000"

    // Ethereum RPC URL (use Infura, Alchemy, etc.)
    private let rpcUrl = "https://mainnet.infura.io/v3/YOUR_INFURA_PROJECT_ID"

    // MARK: - Private

    // private var walletConnect: WalletConnect?
    // private var web3: Web3?

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

    // MARK: - Connection

    /// Connect wallet via WalletConnect
    func connect() async throws {
        isLoading = true
        error = nil

        defer { isLoading = false }

        // WalletConnect implementation:
        // let metadata = AppMetadata(
        //     name: "PM5 Racing",
        //     description: "Compete in rowing races and win crypto",
        //     url: "https://pm5racing.app",
        //     icons: ["https://pm5racing.app/icon.png"]
        // )
        //
        // walletConnect = WalletConnect(
        //     metadata: metadata,
        //     projectId: projectId
        // )
        //
        // let uri = try await walletConnect?.connect()
        // Present URI to user for scanning with wallet app
        //
        // Wait for connection and get address
        // walletAddress = session.accounts.first

        // Mock implementation for testing
        #if DEBUG
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        walletAddress = "0x742d35Cc6634C0532925a3b844Bc9e7595f8fE31"
        isConnected = true
        ethBalance = 0.05 // 0.05 ETH
        #else
        throw WalletError.notImplemented
        #endif
    }

    /// Disconnect wallet
    func disconnect() {
        // walletConnect?.disconnect()
        walletAddress = nil
        isConnected = false
        ethBalance = 0
    }

    // MARK: - Balance

    /// Fetch current ETH balance
    func refreshBalance() async throws {
        guard let address = walletAddress else {
            throw WalletError.notConnected
        }

        // Web3 implementation:
        // let web3 = Web3(rpcURL: rpcUrl)
        // let balance = try await web3.eth.getBalance(address: address)
        // ethBalance = Double(balance) / 1_000_000_000_000_000_000

        // Mock - balance already set in connect()
    }

    // MARK: - ETH Operations

    /// Deposit ETH to escrow for a race
    func depositToEscrow(lobbyId: String, amount: Double) async throws -> String {
        guard walletAddress != nil else {
            throw WalletError.notConnected
        }

        guard ethBalance >= amount else {
            throw WalletError.insufficientBalance
        }

        isLoading = true
        defer { isLoading = false }

        // Web3 implementation:
        // let escrowContract = web3.contract(escrowContractAddress, abiJSON: escrowABI)
        // let lobbyIdBytes = lobbyId.data(using: .utf8)!.sha256()
        // let weiAmount = BigInt(amount * 1_000_000_000_000_000_000)
        // let tx = try escrowContract.write(
        //     "deposit",
        //     parameters: [lobbyIdBytes],
        //     value: weiAmount
        // )
        // let signedTx = try await walletConnect.signTransaction(tx)
        // let txHash = try await web3.eth.sendRawTransaction(signedTx)
        // return txHash

        #if DEBUG
        try await Task.sleep(nanoseconds: 500_000_000)
        ethBalance -= amount
        return "0x\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        #else
        throw WalletError.notImplemented
        #endif
    }

    // MARK: - Signing

    /// Sign a message (for authentication)
    func signMessage(_ message: String) async throws -> String {
        guard walletAddress != nil else {
            throw WalletError.notConnected
        }

        // WalletConnect implementation:
        // let signature = try await walletConnect.personalSign(
        //     message: message,
        //     account: walletAddress!
        // )
        // return signature

        #if DEBUG
        return "0x\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        #else
        throw WalletError.notImplemented
        #endif
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
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Wallet is not connected"
        case .notImplemented:
            return "This feature requires Web3 SDK setup"
        case .connectionFailed:
            return "Failed to connect to wallet"
        case .transactionFailed:
            return "Transaction failed"
        case .insufficientBalance:
            return "Insufficient ETH balance"
        case .userRejected:
            return "Transaction was rejected"
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}
