import Foundation

class DeepLinkManager: ObservableObject {
    @Published var pendingLobbyId: String?

    func handleURL(_ url: URL) {
        guard url.scheme == "pm5racing",
              url.host == "lobby",
              let lobbyId = url.pathComponents.dropFirst().first,
              !lobbyId.isEmpty else {
            return
        }
        pendingLobbyId = lobbyId
    }
}
