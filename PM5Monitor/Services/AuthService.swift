import Foundation
import AuthenticationServices

// MARK: - Concept2 Logbook API Configuration
/*
 ============================================
 CONCEPT2 LOGBOOK API SETUP
 ============================================

 1. Register your app at https://log.concept2.com/developers/keys
 2. Get your Client ID and Client Secret
 3. Set your redirect URI (e.g., pm5monitor://oauth/callback)
 4. Update the configuration below

 API Documentation: https://log.concept2.com/developers/documentation/

 OAuth Flow:
 1. Redirect user to Concept2 authorization URL
 2. User logs in and authorizes
 3. Concept2 redirects back with authorization code
 4. Exchange code for access token
 5. Use access token for API calls

 Available Scopes:
 - user:read - Read user profile
 - user:write - Write user profile
 - results:read - Read workout results
 - results:write - Write workout results

 ============================================
 */

// MARK: - Concept2 API Configuration

struct Concept2Config {
    // IMPORTANT: Replace these with your actual Concept2 API credentials
    static let clientId = "YOUR_CONCEPT2_CLIENT_ID"
    static let clientSecret = "YOUR_CONCEPT2_CLIENT_SECRET"
    static let redirectUri = "pm5monitor://oauth/callback"

    // Use dev environment for testing, production for release
    #if DEBUG
    static let baseUrl = "https://log-dev.concept2.com"
    #else
    static let baseUrl = "https://log.concept2.com"
    #endif

    static let authorizationUrl = "\(baseUrl)/oauth/authorize"
    static let tokenUrl = "\(baseUrl)/oauth/access_token"
    static let userUrl = "\(baseUrl)/api/users/me"

    static let scopes = "user:read results:read"
}

@MainActor
class AuthService: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var currentUser: AuthUser?
    @Published var userProfile: UserProfile?
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var error: AuthError?

    // MARK: - Concept2 OAuth State

    @Published var concept2Profile: Concept2Profile?

    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiry: Date?

    // Keychain keys for secure storage
    private let accessTokenKey = "concept2_access_token"
    private let refreshTokenKey = "concept2_refresh_token"
    private let tokenExpiryKey = "concept2_token_expiry"

    // MARK: - Init

    override init() {
        super.init()
        loadStoredTokens()
    }

    // MARK: - Token Storage

    private func loadStoredTokens() {
        // Load tokens from secure storage (UserDefaults for now, should use Keychain in production)
        accessToken = UserDefaults.standard.string(forKey: accessTokenKey)
        refreshToken = UserDefaults.standard.string(forKey: refreshTokenKey)
        if let expiryInterval = UserDefaults.standard.object(forKey: tokenExpiryKey) as? TimeInterval {
            tokenExpiry = Date(timeIntervalSince1970: expiryInterval)
        }

        // Check if we have a valid session
        if let token = accessToken, let expiry = tokenExpiry, expiry > Date() {
            Task {
                try? await fetchConcept2Profile()
            }
        }
    }

    private func saveTokens(accessToken: String, refreshToken: String?, expiresIn: Int) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenExpiry = Date().addingTimeInterval(TimeInterval(expiresIn))

        // Save to secure storage
        UserDefaults.standard.set(accessToken, forKey: accessTokenKey)
        if let refresh = refreshToken {
            UserDefaults.standard.set(refresh, forKey: refreshTokenKey)
        }
        if let expiry = tokenExpiry {
            UserDefaults.standard.set(expiry.timeIntervalSince1970, forKey: tokenExpiryKey)
        }
    }

    private func clearTokens() {
        accessToken = nil
        refreshToken = nil
        tokenExpiry = nil

        UserDefaults.standard.removeObject(forKey: accessTokenKey)
        UserDefaults.standard.removeObject(forKey: refreshTokenKey)
        UserDefaults.standard.removeObject(forKey: tokenExpiryKey)
    }

    // MARK: - Concept2 OAuth Flow

    /// Get the authorization URL for Concept2 login
    var authorizationURL: URL? {
        var components = URLComponents(string: Concept2Config.authorizationUrl)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: Concept2Config.clientId),
            URLQueryItem(name: "scope", value: Concept2Config.scopes),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Concept2Config.redirectUri)
        ]
        return components?.url
    }

    /// Handle the OAuth callback URL
    func handleOAuthCallback(url: URL) async throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AuthError.invalidCallback
        }

        try await exchangeCodeForToken(code: code)
    }

    /// Exchange authorization code for access token
    private func exchangeCodeForToken(code: String) async throws {
        isLoading = true
        defer { isLoading = false }

        guard let url = URL(string: Concept2Config.tokenUrl) else {
            throw AuthError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "client_id": Concept2Config.clientId,
            "client_secret": Concept2Config.clientSecret,
            "grant_type": "authorization_code",
            "code": code,
            "scope": Concept2Config.scopes,
            "redirect_uri": Concept2Config.redirectUri
        ]

        request.httpBody = body.map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuthError.tokenExchangeFailed
        }

        let tokenResponse = try JSONDecoder().decode(Concept2TokenResponse.self, from: data)

        saveTokens(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            expiresIn: tokenResponse.expiresIn
        )

        try await fetchConcept2Profile()
    }

    /// Refresh the access token
    func refreshAccessToken() async throws {
        guard let refresh = refreshToken else {
            throw AuthError.notAuthenticated
        }

        guard let url = URL(string: Concept2Config.tokenUrl) else {
            throw AuthError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "client_id": Concept2Config.clientId,
            "client_secret": Concept2Config.clientSecret,
            "grant_type": "refresh_token",
            "refresh_token": refresh
        ]

        request.httpBody = body.map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            // Refresh failed, clear tokens and require re-login
            clearTokens()
            isAuthenticated = false
            throw AuthError.tokenRefreshFailed
        }

        let tokenResponse = try JSONDecoder().decode(Concept2TokenResponse.self, from: data)

        saveTokens(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            expiresIn: tokenResponse.expiresIn
        )
    }

    /// Fetch the user's Concept2 profile
    func fetchConcept2Profile() async throws {
        guard let token = accessToken else {
            throw AuthError.notAuthenticated
        }

        // Check if token needs refresh
        if let expiry = tokenExpiry, expiry < Date() {
            try await refreshAccessToken()
        }

        guard let url = URL(string: Concept2Config.userUrl) else {
            throw AuthError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken ?? token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuthError.profileFetchFailed
        }

        let apiResponse = try JSONDecoder().decode(Concept2UserResponse.self, from: data)
        concept2Profile = apiResponse.data

        // Create local user and profile from Concept2 data
        currentUser = AuthUser(
            id: String(concept2Profile!.id),
            email: concept2Profile?.email,
            displayName: "\(concept2Profile?.firstName ?? "") \(concept2Profile?.lastName ?? "")".trimmingCharacters(in: .whitespaces)
        )

        userProfile = UserProfile(
            id: String(concept2Profile!.id),
            email: concept2Profile?.email,
            displayName: currentUser?.displayName ?? "Rower",
            concept2Id: concept2Profile?.id,
            lifetimeMeters: concept2Profile?.lifetimeMeters ?? 0
        )

        isAuthenticated = true
    }

    /// Sign out
    func signOut() throws {
        clearTokens()
        currentUser = nil
        userProfile = nil
        concept2Profile = nil
        isAuthenticated = false
    }

    // MARK: - Wallet Integration

    /// Link a wallet address to the user profile
    func linkWallet(address: String) async throws {
        guard var profile = userProfile else {
            throw AuthError.notAuthenticated
        }

        profile.walletAddress = address
        userProfile = profile
    }

    /// Unlink wallet from user profile
    func unlinkWallet() async throws {
        guard var profile = userProfile else {
            throw AuthError.notAuthenticated
        }

        profile.walletAddress = nil
        userProfile = profile
    }
}

// MARK: - Concept2 API Response Models

struct Concept2TokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

struct Concept2UserResponse: Codable {
    let data: Concept2Profile
}

struct Concept2Profile: Codable {
    let id: Int
    let username: String?
    let firstName: String?
    let lastName: String?
    let email: String?
    let gender: String?
    let dob: String?
    let profileImage: String?
    let lifetimeMeters: Int?

    enum CodingKeys: String, CodingKey {
        case id, username, email, gender, dob
        case firstName = "first_name"
        case lastName = "last_name"
        case profileImage = "profile_image"
        case lifetimeMeters = "lifetime_meters"
    }
}

// MARK: - Auth User

struct AuthUser: Identifiable {
    let id: String
    let email: String?
    let displayName: String?
}

// MARK: - Auth Error

enum AuthError: LocalizedError {
    case notAuthenticated
    case notImplemented
    case invalidCallback
    case invalidConfiguration
    case tokenExchangeFailed
    case tokenRefreshFailed
    case profileFetchFailed
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to perform this action"
        case .notImplemented:
            return "This feature is not yet implemented"
        case .invalidCallback:
            return "Invalid OAuth callback"
        case .invalidConfiguration:
            return "Invalid API configuration"
        case .tokenExchangeFailed:
            return "Failed to exchange authorization code"
        case .tokenRefreshFailed:
            return "Session expired. Please sign in again."
        case .profileFetchFailed:
            return "Failed to fetch Concept2 profile"
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}
