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
    @Published var usdcBalance: UInt64 = 0  // In smallest units (6 decimals)
    @Published var ethBalance: UInt64 = 0   // In wei
    @Published var isLoading = false
    @Published var error: WalletError?

    // MARK: - Configuration

    // WalletConnect Project ID - Get from https://cloud.walletconnect.com
    private let projectId = "YOUR_WALLETCONNECT_PROJECT_ID"

    // USDC Contract on Ethereum Mainnet
    private let usdcContractAddress = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"

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

    var formattedUSDCBalance: String {
        let usdc = Double(usdcBalance) / 1_000_000
        return String(format: "$%.2f", usdc)
    }

    var formattedETHBalance: String {
        let eth = Double(ethBalance) / 1_000_000_000_000_000_000
        return String(format: "%.4f ETH", eth)
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
        usdcBalance = 150_000_000 // 150 USDC
        ethBalance = 50_000_000_000_000_000 // 0.05 ETH
        #else
        throw WalletError.notImplemented
        #endif
    }

    /// Disconnect wallet
    func disconnect() {
        // walletConnect?.disconnect()
        walletAddress = nil
        isConnected = false
        usdcBalance = 0
        ethBalance = 0
    }

    // MARK: - Balance

    /// Fetch current balances
    func refreshBalances() async throws {
        guard let address = walletAddress else {
            throw WalletError.notConnected
        }

        // Web3 implementation:
        // let web3 = Web3(rpcURL: rpcUrl)
        //
        // // Get ETH balance
        // let ethBalance = try await web3.eth.getBalance(address: address)
        //
        // // Get USDC balance (ERC20)
        // let usdcContract = web3.contract(usdcContractAddress, abiJSON: erc20ABI)
        // let usdcBalance = try await usdcContract.call("balanceOf", parameters: [address])

        // Mock - balances already set in connect()
    }

    // MARK: - USDC Operations

    /// Approve USDC spending by escrow contract
    func approveUSDC(amount: UInt64) async throws -> String {
        guard walletAddress != nil else {
            throw WalletError.notConnected
        }

        isLoading = true
        defer { isLoading = false }

        // Web3 implementation:
        // let usdcContract = web3.contract(usdcContractAddress, abiJSON: erc20ABI)
        // let tx = try usdcContract.write(
        //     "approve",
        //     parameters: [escrowContractAddress, amount]
        // )
        // let signedTx = try await walletConnect.signTransaction(tx)
        // let txHash = try await web3.eth.sendRawTransaction(signedTx)
        // return txHash

        #if DEBUG
        try await Task.sleep(nanoseconds: 500_000_000)
        return "0x\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        #else
        throw WalletError.notImplemented
        #endif
    }

    /// Deposit USDC to escrow for a race
    func depositToEscrow(lobbyId: String, amount: UInt64) async throws -> String {
        guard walletAddress != nil else {
            throw WalletError.notConnected
        }

        isLoading = true
        defer { isLoading = false }

        // First approve USDC spending
        _ = try await approveUSDC(amount: amount)

        // Web3 implementation:
        // let escrowContract = web3.contract(escrowContractAddress, abiJSON: escrowABI)
        // let lobbyIdBytes = lobbyId.data(using: .utf8)!.sha256()
        // let tx = try escrowContract.write(
        //     "deposit",
        //     parameters: [lobbyIdBytes]
        // )
        // let signedTx = try await walletConnect.signTransaction(tx)
        // let txHash = try await web3.eth.sendRawTransaction(signedTx)
        // return txHash

        #if DEBUG
        try await Task.sleep(nanoseconds: 500_000_000)
        usdcBalance -= amount
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
            return "Insufficient balance"
        case .userRejected:
            return "Transaction was rejected"
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}

// MARK: - ERC20 ABI (partial)

private let erc20ABI = """
[
    {
        "constant": true,
        "inputs": [{"name": "_owner", "type": "address"}],
        "name": "balanceOf",
        "outputs": [{"name": "balance", "type": "uint256"}],
        "type": "function"
    },
    {
        "constant": false,
        "inputs": [
            {"name": "_spender", "type": "address"},
            {"name": "_value", "type": "uint256"}
        ],
        "name": "approve",
        "outputs": [{"name": "", "type": "bool"}],
        "type": "function"
    }
]
"""
