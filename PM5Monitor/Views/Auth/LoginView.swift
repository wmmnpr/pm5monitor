import SwiftUI

struct LoginView: View {
    @ObservedObject var authService: AuthService
    @State private var displayName = ""
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
                VStack(spacing: 20) {
                    // Erg5 Logo
                    Erg5Logo()

                    Text("Compete. Win. Earn.")
                        .font(.title3)
                        .foregroundColor(.gray)
                }

                Spacer()

                // Login content
                VStack(spacing: 20) {
                    // Name input
                    TextField("Enter your name", text: $displayName)
                        .textFieldStyle(.plain)
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.cyan.opacity(0.5), lineWidth: 1)
                        )
                        .padding(.horizontal, 32)
                        .autocorrectionDisabled()

                    // Quick Start button
                    Button {
                        let name = displayName.trimmingCharacters(in: .whitespaces)
                        authService.signInAsGuest(displayName: name.isEmpty ? "Rower" : name)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "play.fill")
                                .font(.title3)
                            Text("Start Racing")
                                .font(.headline)
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.cyan)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 32)
                }

                Spacer()

                // Footer
                VStack(spacing: 8) {
                    Text("Race against friends and bots")
                        .font(.caption)
                        .foregroundColor(.gray)

                    Text("Connect your PM5 via Bluetooth")
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.7))
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
                    Text("Starting...")
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

// MARK: - Erg5 Logo

struct Erg5Logo: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 8) {
            // Main logo container
            ZStack {
                // Outer glow ring
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [.cyan, .blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 3
                    )
                    .frame(width: 120, height: 120)
                    .blur(radius: 4)
                    .opacity(isAnimating ? 0.8 : 0.4)

                // Inner circle background
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.cyan.opacity(0.3), Color.black],
                            center: .center,
                            startRadius: 0,
                            endRadius: 60
                        )
                    )
                    .frame(width: 110, height: 110)

                // Icon
                Image(systemName: "oar.2.crossed")
                    .font(.system(size: 50, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .cyan],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .cyan.opacity(0.5), radius: 10)
            }

            // ERG5 Text
            HStack(spacing: 2) {
                Text("ERG")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .gray],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Text("5")
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .blue],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .cyan.opacity(0.8), radius: 8)
            }

            // Subtitle
            Text("RACING")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .tracking(8)
                .foregroundColor(.gray)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

#Preview {
    LoginView(authService: AuthService())
}

#Preview("Logo Only") {
    ZStack {
        Color.black.ignoresSafeArea()
        Erg5Logo()
    }
}
