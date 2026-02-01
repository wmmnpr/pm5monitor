import SwiftUI

@main
struct PM5MonitorApp: App {
    @StateObject private var deepLinkManager = DeepLinkManager()

    init() {
        // Initialize Firebase
        FirebaseConfig.configure()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView(deepLinkManager: deepLinkManager)
                .onOpenURL { url in
                    deepLinkManager.handleURL(url)
                }
        }
    }
}
