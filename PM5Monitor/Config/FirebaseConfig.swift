import Foundation

// MARK: - Firebase Setup Instructions
/*
 ============================================
 FIREBASE SETUP GUIDE
 ============================================

 1. ADD FIREBASE SDK TO PROJECT:
    - In Xcode: File > Add Package Dependencies
    - Enter URL: https://github.com/firebase/firebase-ios-sdk.git
    - Select version: 10.0.0 or later
    - Choose products: FirebaseAuth, FirebaseFirestore

 2. CREATE FIREBASE PROJECT:
    - Go to https://console.firebase.google.com
    - Click "Add project" and follow setup
    - Add iOS app with bundle ID: com.example.PM5Monitor
    - Download GoogleService-Info.plist
    - Drag it into your Xcode project (PM5Monitor folder)

 3. ENABLE AUTHENTICATION:
    - In Firebase Console > Authentication > Sign-in method
    - Enable "Apple" provider
    - Add your Apple Team ID and Service ID

 4. SETUP FIRESTORE:
    - In Firebase Console > Firestore Database
    - Create database (start in test mode for development)
    - Deploy security rules from firestore.rules file

 5. UNCOMMENT FIREBASE CODE:
    - Once SDK is added, uncomment imports in:
      - FirebaseConfig.swift
      - AuthService.swift
      - LobbyService.swift
      - RaceService.swift

 ============================================
 */

// Uncomment after adding Firebase SDK:
// import FirebaseCore
// import FirebaseAuth
// import FirebaseFirestore

/// Firebase configuration and initialization
class FirebaseConfig {
    static let shared = FirebaseConfig()

    // Uncomment after adding Firebase SDK:
    // let db: Firestore
    // let auth: Auth

    private init() {
        // Uncomment after adding Firebase SDK:
        // FirebaseApp.configure()
        // db = Firestore.firestore()
        // auth = Auth.auth()

        // Configure Firestore settings
        // let settings = FirestoreSettings()
        // settings.cacheSettings = PersistentCacheSettings()
        // db.settings = settings
    }

    /// Call this in App init to configure Firebase
    static func configure() {
        // Uncomment after adding Firebase SDK:
        // FirebaseApp.configure()
        _ = shared
    }
}

// MARK: - Firestore Collection References

extension FirebaseConfig {
    // Uncomment after adding Firebase SDK:
    // var usersCollection: CollectionReference {
    //     db.collection("users")
    // }
    //
    // var lobbiesCollection: CollectionReference {
    //     db.collection("lobbies")
    // }
    //
    // var racesCollection: CollectionReference {
    //     db.collection("races")
    // }
    //
    // func participantsCollection(lobbyId: String) -> CollectionReference {
    //     lobbiesCollection.document(lobbyId).collection("participants")
    // }
    //
    // func raceUpdatesCollection(raceId: String) -> CollectionReference {
    //     racesCollection.document(raceId).collection("updates")
    // }
    //
    // func raceResultsCollection(raceId: String) -> CollectionReference {
    //     racesCollection.document(raceId).collection("results")
    // }
}
