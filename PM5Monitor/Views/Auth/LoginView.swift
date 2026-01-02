import SwiftUI

struct LoginView: View {
    @ObservedObject var authService: AuthService
    @State private var showWebView = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.black, Color.blue.opacity(0.3), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // Logo and title
                VStack(spacing: 16) {
                    Image(systemName: "figure.rowing")
                        .font(.system(size: 80))
                        .foregroundColor(.cyan)

                    Text("PM5 Racing")
                        .font(.largeTitle.bold())
                        .foregroundColor(.white)

                    Text("Compete. Win. Earn.")
                        .font(.title3)
                        .foregroundColor(.gray)
                }

                Spacer()

                // Login content
                VStack(spacing: 24) {
                    // Concept2 info
                    VStack(spacing: 8) {
                        Image(systemName: "person.badge.key.fill")
                            .font(.title)
                            .foregroundColor(.cyan)

                        Text("Sign in with your Concept2 Logbook account")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }

                    // Sign in with Concept2 button
                    Button {
                        showWebView = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "link.circle.fill")
                                .font(.title2)

                            Text("Sign in with Concept2")
                                .font(.headline)
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.white)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 32)

                    // Create account link
                    VStack(spacing: 8) {
                        Text("Don't have an account?")
                            .font(.caption)
                            .foregroundColor(.gray)

                        Link("Create a free Concept2 Logbook account", destination: URL(string: "https://log.concept2.com/register")!)
                            .font(.caption)
                            .foregroundColor(.cyan)
                    }
                }

                Spacer()

                // Footer
                VStack(spacing: 8) {
                    Text("By signing in, you agree to our")
                        .font(.caption2)
                        .foregroundColor(.gray)

                    HStack(spacing: 4) {
                        Link("Terms of Service", destination: URL(string: "https://pm5racing.app/terms")!)
                        Text("and")
                            .foregroundColor(.gray)
                        Link("Privacy Policy", destination: URL(string: "https://pm5racing.app/privacy")!)
                    }
                    .font(.caption2)
                    .foregroundColor(.cyan)
                }
                .padding(.bottom, 32)
            }

            // Loading overlay
            if authService.isLoading {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text("Signing in...")
                        .foregroundColor(.white)
                }
            }
        }
        .sheet(isPresented: $showWebView) {
            Concept2WebView(authService: authService, isPresented: $showWebView)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onReceive(authService.$error.compactMap { $0 }) { error in
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Concept2 Web View for OAuth

import WebKit

struct Concept2WebView: UIViewRepresentable {
    @ObservedObject var authService: AuthService
    @Binding var isPresented: Bool

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator

        if let url = authService.authorizationURL {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: Concept2WebView

        init(_ parent: Concept2WebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {

            if let url = navigationAction.request.url,
               url.scheme == "pm5monitor" && url.host == "oauth" {
                // Handle OAuth callback
                Task { @MainActor in
                    do {
                        try await self.parent.authService.handleOAuthCallback(url: url)
                        self.parent.isPresented = false
                    } catch {
                        // Error is handled via authService.error
                    }
                }
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }
    }
}

#Preview {
    LoginView(authService: AuthService())
}
