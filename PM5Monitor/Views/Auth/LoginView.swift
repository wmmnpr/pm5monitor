import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @ObservedObject var authService: AuthService
    @State private var showError = false

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.black, Color.blue.opacity(0.3)],
                startPoint: .top,
                endPoint: .bottom
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
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)

                    Text("Compete. Win. Earn.")
                        .font(.title3)
                        .foregroundColor(.gray)
                }

                Spacer()

                // Features
                VStack(alignment: .leading, spacing: 16) {
                    FeatureRow(icon: "person.3.fill", text: "Race against rowers worldwide")
                    FeatureRow(icon: "bitcoinsign.circle.fill", text: "Win crypto prizes")
                    FeatureRow(icon: "chart.line.uptrend.xyaxis", text: "Track your performance")
                }
                .padding(.horizontal, 32)

                Spacer()

                // Sign in buttons
                VStack(spacing: 16) {
                    // Sign in with Apple
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.email, .fullName]
                    } onCompletion: { result in
                        handleAppleSignIn(result)
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 54)
                    .cornerRadius(12)

                    // Guest sign in (for testing)
                    Button {
                        Task {
                            do {
                                try await authService.signInAnonymously()
                            } catch {
                                showError = true
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "person.crop.circle.badge.questionmark")
                            Text("Continue as Guest")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 24)

                // Terms
                Text("By continuing, you agree to our Terms of Service and Privacy Policy")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 32)
            }
        }
        .alert("Sign In Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(authService.error?.localizedDescription ?? "Please try again")
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            Task {
                do {
                    try await authService.signInWithApple()
                } catch {
                    showError = true
                }
            }
        case .failure(let error):
            print("Apple Sign In failed: \(error)")
            showError = true
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.cyan)
                .frame(width: 32)

            Text(text)
                .font(.body)
                .foregroundColor(.white)
        }
    }
}

#Preview {
    LoginView(authService: AuthService())
}
