import Foundation
import AuthenticationServices

// MARK: - Sign in with Apple Setup
/*
 ============================================
 SIGN IN WITH APPLE SETUP
 ============================================

 1. In Xcode, go to your target's "Signing & Capabilities"
 2. Click "+ Capability" and add "Sign in with Apple"
 3. Make sure your Apple Developer account has this enabled

 That's it! No external configuration needed.

 ============================================
 */

@MainActor
class AuthService: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var currentUser: AuthUser?
    @Published var userProfile: UserProfile?
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var error: AuthError?

    // MARK: - Private

    private let userDefaultsKey = "pm5_current_user"

    // MARK: - Init

    override init() {
        super.init()
        loadStoredUser()
    }

    // MARK: - Stored User

    private func loadStoredUser() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let user = try? JSONDecoder().decode(StoredUser.self, from: data) {
            currentUser = AuthUser(
                id: user.id,
                email: user.email,
                displayName: user.displayName
            )
            userProfile = UserProfile(
                id: user.id,
                email: user.email,
                displayName: user.displayName ?? "Rower"
            )
            isAuthenticated = true
        }
    }

    private func saveUser(_ user: AuthUser) {
        let storedUser = StoredUser(
            id: user.id,
            email: user.email,
            displayName: user.displayName
        )
        if let data = try? JSONEncoder().encode(storedUser) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    private func clearStoredUser() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }

    // MARK: - Sign In with Apple

    func signInWithApple() {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.performRequests()

        isLoading = true
        error = nil
    }

    /// Sign out
    func signOut() throws {
        clearStoredUser()
        currentUser = nil
        userProfile = nil
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

// MARK: - ASAuthorizationControllerDelegate

extension AuthService: ASAuthorizationControllerDelegate {

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            isLoading = false

            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                error = .appleSignInFailed
                return
            }

            let userId = appleIDCredential.user

            // Get name (only available on first sign in)
            var displayName: String? = nil
            if let fullName = appleIDCredential.fullName {
                let givenName = fullName.givenName ?? ""
                let familyName = fullName.familyName ?? ""
                displayName = "\(givenName) \(familyName)".trimmingCharacters(in: .whitespaces)
                if displayName?.isEmpty == true {
                    displayName = nil
                }
            }

            // Get email (only available on first sign in)
            let email = appleIDCredential.email

            // If we have a stored user with this ID, use their stored name
            if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
               let storedUser = try? JSONDecoder().decode(StoredUser.self, from: data),
               storedUser.id == userId {
                displayName = displayName ?? storedUser.displayName
            }

            let user = AuthUser(
                id: userId,
                email: email,
                displayName: displayName
            )

            currentUser = user
            userProfile = UserProfile(
                id: userId,
                email: email,
                displayName: displayName ?? "Rower"
            )
            isAuthenticated = true

            saveUser(user)
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            isLoading = false

            if let authError = error as? ASAuthorizationError {
                switch authError.code {
                case .canceled:
                    // User canceled, don't show error
                    return
                default:
                    self.error = .appleSignInFailed
                }
            } else {
                self.error = .unknown(error)
            }
        }
    }
}

// MARK: - Stored User (for persistence)

private struct StoredUser: Codable {
    let id: String
    let email: String?
    let displayName: String?
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
    case appleSignInFailed
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to perform this action"
        case .appleSignInFailed:
            return "Sign in with Apple failed. Please try again."
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}
