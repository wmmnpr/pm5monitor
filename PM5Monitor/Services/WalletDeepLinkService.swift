import Foundation
import UIKit

/// Service for generating and opening wallet deep links for crypto transfers
struct WalletDeepLinkService {

    /// Network configuration
    enum Network {
        case mainnet
        case sepolia

        var chainId: Int {
            switch self {
            case .mainnet: return 1
            case .sepolia: return 11155111
            }
        }

        var name: String {
            switch self {
            case .mainnet: return "Ethereum Mainnet"
            case .sepolia: return "Sepolia Testnet"
            }
        }
    }

    /// Current network - change this for testing
    static let currentNetwork: Network = .sepolia

    /// Supported wallet apps for deep linking
    enum WalletApp: String, CaseIterable, Identifiable {
        case metamask = "metamask"
        case rainbow = "rainbow"
        case coinbase = "coinbase"
        case trust = "trust"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .metamask: return "MetaMask"
            case .rainbow: return "Rainbow"
            case .coinbase: return "Coinbase Wallet"
            case .trust: return "Trust Wallet"
            }
        }

        var iconName: String {
            switch self {
            case .metamask: return "m.square.fill"
            case .rainbow: return "rainbow"
            case .coinbase: return "c.square.fill"
            case .trust: return "shield.fill"
            }
        }

        /// URL scheme for the wallet app
        var urlScheme: String {
            switch self {
            case .metamask: return "metamask://"
            case .rainbow: return "rainbow://"
            case .coinbase: return "cbwallet://"
            case .trust: return "trust://"
            }
        }

        /// Check if the wallet app is installed
        func isInstalled() -> Bool {
            guard let url = URL(string: urlScheme) else { return false }
            return UIApplication.shared.canOpenURL(url)
        }

        /// Generate a deep link URL for sending ETH
        /// - Parameters:
        ///   - toAddress: Recipient wallet address
        ///   - amount: Amount in ETH (optional - user can set in wallet)
        /// - Returns: Deep link URL if supported
        func sendETHURL(toAddress: String, amount: Double? = nil) -> URL? {
            // Validate address
            guard toAddress.hasPrefix("0x") && toAddress.count == 42 else {
                return nil
            }

            let chainId = WalletDeepLinkService.currentNetwork.chainId
            var urlString: String

            switch self {
            case .metamask:
                // MetaMask deep link with EIP-681 format for network selection
                // Format: https://metamask.app.link/send/<address>@<chainId>?value=<wei>
                if let amount = amount {
                    let weiAmount = UInt64(amount * 1_000_000_000_000_000_000)
                    urlString = "https://metamask.app.link/send/\(toAddress)@\(chainId)?value=\(weiAmount)"
                } else {
                    urlString = "https://metamask.app.link/send/\(toAddress)@\(chainId)"
                }

            case .rainbow:
                // Rainbow wallet deep link
                if let amount = amount {
                    urlString = "rainbow://send?address=\(toAddress)&amount=\(amount)&chainId=\(chainId)"
                } else {
                    urlString = "rainbow://send?address=\(toAddress)&chainId=\(chainId)"
                }

            case .coinbase:
                // Coinbase Wallet deep link with chain ID
                urlString = "cbwallet://send?address=\(toAddress)&chainId=\(chainId)"
                if let amount = amount {
                    urlString += "&amount=\(amount)"
                }

            case .trust:
                // Trust Wallet deep link with chain ID
                if let amount = amount {
                    let weiAmount = UInt64(amount * 1_000_000_000_000_000_000)
                    urlString = "trust://send?coin=60&address=\(toAddress)&amount=\(weiAmount)&chainId=\(chainId)"
                } else {
                    urlString = "trust://send?coin=60&address=\(toAddress)&chainId=\(chainId)"
                }
            }

            return URL(string: urlString)
        }
    }

    /// Get list of installed wallet apps
    static func installedWallets() -> [WalletApp] {
        WalletApp.allCases.filter { $0.isInstalled() }
    }

    /// Open wallet app to send ETH
    /// - Parameters:
    ///   - wallet: The wallet app to use
    ///   - toAddress: Recipient wallet address
    ///   - amount: Amount in ETH (optional)
    /// - Returns: Whether the URL was opened successfully
    @discardableResult
    static func openWalletToSend(wallet: WalletApp, toAddress: String, amount: Double? = nil) -> Bool {
        guard let url = wallet.sendETHURL(toAddress: toAddress, amount: amount) else {
            print("[WalletDeepLink] ERROR: Failed to generate URL for \(wallet.displayName)")
            return false
        }

        print("[WalletDeepLink] Generated URL: \(url.absoluteString)")
        print("[WalletDeepLink] Network: \(currentNetwork.name) (chainId: \(currentNetwork.chainId))")
        print("[WalletDeepLink] Wallet: \(wallet.displayName), To: \(toAddress), Amount: \(amount ?? 0) ETH")

        if UIApplication.shared.canOpenURL(url) {
            print("[WalletDeepLink] Opening URL...")
            UIApplication.shared.open(url, options: [:]) { success in
                print("[WalletDeepLink] Open result: \(success)")
            }
            return true
        }

        print("[WalletDeepLink] Cannot open URL - wallet may not be installed")
        return false
    }

    /// Generate a universal Ethereum URI (EIP-681) for any wallet
    /// Format: ethereum:<address>[@chainId][/function]?[parameters]
    static func ethereumURI(toAddress: String, amount: Double? = nil, chainId: Int = 1) -> URL? {
        guard toAddress.hasPrefix("0x") && toAddress.count == 42 else {
            return nil
        }

        var urlString = "ethereum:\(toAddress)@\(chainId)"

        if let amount = amount {
            let weiAmount = UInt64(amount * 1_000_000_000_000_000_000)
            urlString += "?value=\(weiAmount)"
        }

        return URL(string: urlString)
    }
}
