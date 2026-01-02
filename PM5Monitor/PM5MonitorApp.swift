import SwiftUI

@main
struct PM5MonitorApp: App {

    init() {
        // Initialize Firebase
        FirebaseConfig.configure()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}
