import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @ObservedObject var authService: AuthService
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
                    // Sign in with Apple button
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { _ in
                        // Handled by AuthService delegate
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 54)
                    .cornerRadius(12)
                    .padding(.horizontal, 32)
                    .onTapGesture {
                        authService.signInWithApple()
                    }

                    // Alternative: Custom styled button that triggers sign in
                    Button {
                        authService.signInWithApple()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "applelogo")
                                .font(.title2)
                            Text("Sign in with Apple")
                                .font(.headline)
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.white)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 32)
                }

                Spacer()

                // Footer
                VStack(spacing: 8) {
                    Text("By signing in, you agree to our")
                        .font(.caption2)
                        .foregroundColor(.gray)

                    HStack(spacing: 4) {
                        Text("Terms of Service")
                            .foregroundColor(.cyan)
                        Text("and")
                            .foregroundColor(.gray)
                        Text("Privacy Policy")
                            .foregroundColor(.cyan)
                    }
                    .font(.caption2)
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

#Preview {
    LoginView(authService: AuthService())
}
