import SwiftUI

struct SignInView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss

    private enum Mode {
        case signIn, signUp
    }

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var isEmailFormValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && password.count >= 6
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Sign in to Agdayo")
                        .font(AppFont.outfit(24, weight: .bold, relativeTo: .title2))
                    Text("Invite friends to trips and share your journey.")
                        .font(AppFont.outfit(14, relativeTo: .subheadline))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 16)

                Button {
                    Task { await handleGoogleSignIn() }
                } label: {
                    HStack {
                        Image("GoogleLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                        Text("Continue with Google")
                    }
                }
                .buttonStyle(.appSecondary)
                .disabled(isLoading)

                HStack {
                    Rectangle().fill(Color(.systemGray4)).frame(height: 1)
                    Text("or").font(AppFont.outfit(12, relativeTo: .caption)).foregroundStyle(.secondary)
                    Rectangle().fill(Color(.systemGray4)).frame(height: 1)
                }

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .modifier(GlassOrStickerCard(cornerRadius: AppRadius.denseCard))

                    SecureField("Password", text: $password)
                        .textContentType(mode == .signIn ? .password : .newPassword)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .modifier(GlassOrStickerCard(cornerRadius: AppRadius.denseCard))
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(AppFont.outfit(12, relativeTo: .caption))
                        .foregroundStyle(Color.appDanger)
                        .multilineTextAlignment(.center)
                }

                Button(mode == .signIn ? "Sign In" : "Create Account") {
                    Task { await handleEmailSubmit() }
                }
                .buttonStyle(.appPrimary)
                .disabled(!isEmailFormValid || isLoading)

                Button {
                    mode = mode == .signIn ? .signUp : .signIn
                    errorMessage = nil
                } label: {
                    Text(mode == .signIn ? "No account yet? Sign Up" : "Already have an account? Sign In")
                        .font(AppFont.outfit(13, relativeTo: .footnote))
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if isLoading {
                    ProgressView()
                }
            }
        }
    }

    private func handleGoogleSignIn() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await authService.signInWithGoogle()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleEmailSubmit() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            switch mode {
            case .signIn:
                try await authService.signIn(email: email, password: password)
            case .signUp:
                try await authService.signUp(email: email, password: password)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
