import Foundation
import AuthenticationServices

// MARK: - Firebase Setup Instructions
/*
 To enable Firebase Authentication:

 1. Open Xcode, go to File > Add Package Dependencies
 2. Add: https://github.com/firebase/firebase-ios-sdk.git
 3. Select: FirebaseAuth, FirebaseFirestore
 4. Create a Firebase project at https://console.firebase.google.com
 5. Download GoogleService-Info.plist and add to project
 6. Uncomment the Firebase imports and implementation below
 */

// import FirebaseAuth
// import FirebaseFirestore

@MainActor
class AuthService: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var currentUser: AuthUser?
    @Published var userProfile: UserProfile?
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var error: AuthError?

    // MARK: - Private

    // private let auth = Auth.auth()
    // private let db = Firestore.firestore()
    private var authStateListener: Any?

    // MARK: - Init

    override init() {
        super.init()
        setupAuthStateListener()
    }

    deinit {
        // Remove auth state listener
    }

    // MARK: - Auth State

    private func setupAuthStateListener() {
        // Firebase implementation:
        // authStateListener = auth.addStateDidChangeListener { [weak self] _, user in
        //     Task { @MainActor in
        //         if let user = user {
        //             self?.currentUser = AuthUser(firebaseUser: user)
        //             self?.isAuthenticated = true
        //             try? await self?.fetchUserProfile()
        //         } else {
        //             self?.currentUser = nil
        //             self?.userProfile = nil
        //             self?.isAuthenticated = false
        //         }
        //     }
        // }

        // Mock implementation for testing
        #if DEBUG
        // Simulate logged out state
        isAuthenticated = false
        #endif
    }

    // MARK: - Sign In Methods

    /// Sign in with Apple
    func signInWithApple() async throws {
        isLoading = true
        error = nil

        defer { isLoading = false }

        // Firebase implementation would use ASAuthorizationController
        // and then sign in with Firebase using the Apple credential

        throw AuthError.notImplemented
    }

    /// Sign in anonymously (for testing)
    func signInAnonymously() async throws {
        isLoading = true
        error = nil

        defer { isLoading = false }

        // Firebase implementation:
        // let result = try await auth.signInAnonymously()
        // currentUser = AuthUser(firebaseUser: result.user)
        // try await createUserProfile(for: result.user)

        // Mock implementation
        #if DEBUG
        let mockUser = AuthUser(
            id: UUID().uuidString,
            email: nil,
            displayName: "Guest"
        )
        currentUser = mockUser
        userProfile = UserProfile(
            id: mockUser.id,
            displayName: "Guest \(Int.random(in: 1000...9999))"
        )
        isAuthenticated = true
        #else
        throw AuthError.notImplemented
        #endif
    }

    /// Sign out
    func signOut() throws {
        // Firebase implementation:
        // try auth.signOut()

        currentUser = nil
        userProfile = nil
        isAuthenticated = false
    }

    // MARK: - User Profile

    /// Fetch user profile from Firestore
    func fetchUserProfile() async throws {
        guard let userId = currentUser?.id else {
            throw AuthError.notAuthenticated
        }

        // Firebase implementation:
        // let doc = try await db.collection("users").document(userId).getDocument()
        // userProfile = try doc.data(as: UserProfile.self)

        // Mock implementation - already set in signInAnonymously
    }

    /// Create user profile in Firestore
    private func createUserProfile(for userId: String, displayName: String) async throws {
        let profile = UserProfile(
            id: userId,
            displayName: displayName
        )

        // Firebase implementation:
        // try db.collection("users").document(userId).setData(from: profile)

        userProfile = profile
    }

    /// Update display name
    func updateDisplayName(_ name: String) async throws {
        guard var profile = userProfile else {
            throw AuthError.notAuthenticated
        }

        profile.displayName = name

        // Firebase implementation:
        // try await db.collection("users").document(profile.id).updateData([
        //     "displayName": name
        // ])

        userProfile = profile
    }

    // MARK: - Wallet Integration

    /// Link a wallet address to the user profile
    func linkWallet(address: String) async throws {
        guard var profile = userProfile else {
            throw AuthError.notAuthenticated
        }

        profile.walletAddress = address

        // Firebase implementation:
        // try await db.collection("users").document(profile.id).updateData([
        //     "walletAddress": address
        // ])

        userProfile = profile
    }

    /// Unlink wallet from user profile
    func unlinkWallet() async throws {
        guard var profile = userProfile else {
            throw AuthError.notAuthenticated
        }

        profile.walletAddress = nil

        // Firebase implementation:
        // try await db.collection("users").document(profile.id).updateData([
        //     "walletAddress": FieldValue.delete()
        // ])

        userProfile = profile
    }
}

// MARK: - Auth User

struct AuthUser: Identifiable {
    let id: String
    let email: String?
    let displayName: String?

    // Firebase implementation:
    // init(firebaseUser: User) {
    //     self.id = firebaseUser.uid
    //     self.email = firebaseUser.email
    //     self.displayName = firebaseUser.displayName
    // }
}

// MARK: - Auth Error

enum AuthError: LocalizedError {
    case notAuthenticated
    case notImplemented
    case appleSignInFailed
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to perform this action"
        case .notImplemented:
            return "This feature requires Firebase setup"
        case .appleSignInFailed:
            return "Sign in with Apple failed"
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        // Handle successful Apple Sign In
        // Convert to Firebase credential and sign in
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            self.error = .appleSignInFailed
        }
    }
}
