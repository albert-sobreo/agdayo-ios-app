import AuthenticationServices
import SwiftUI
import SwiftData
import FirebaseAuth

/// The About You form is a local SwiftData `UserProfile`, with one exception:
/// when signed in, Full Name is also saved to the account (Firebase Auth and
/// `users/{uid}`), because that is the name other travelers see. A singleton
/// UserProfile row is lazily created on first appear if none exists yet.
struct ProfileView: View {
    @Query private var profiles: [UserProfile]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if let profile = profiles.first {
                ProfileForm(profile: profile)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(BrandPalette.canvas.ignoresSafeArea())
            }
        }
        .navigationTitle("Profile")
        .task {
            if profiles.isEmpty {
                modelContext.insert(UserProfile())
            }
        }
    }
}

private struct ProfileForm: View {
    @Bindable var profile: UserProfile
    @Environment(AuthService.self) private var authService
    @Environment(\.modelContext) private var modelContext
    @Query private var trips: [Trip]
    @State private var appUserProfile: AppUserProfile?
    @State private var isPresentingSignIn = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingReauthPassword = false
    @State private var isShowingReauthApple = false
    @State private var isDeletingAccount = false
    @State private var isShowingDeleteError = false
    @State private var deleteAccountErrorMessage = ""
    @State private var nameSyncState: NameSyncState = .idle
    @AppStorage(NotificationScheduler.remindersEnabledKey) private var remindersEnabled = true

    var body: some View {
        Form {
            Section("Account") {
                accountSectionContent
            }

            // Finished trips, as poster cards.
            Section {
                TripShowcaseSection(trips: trips)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } header: {
                MoneySectionHeader(title: "Trips with Agdayo", iconName: "airplane.departure", accentColor: .appPrimary)
            }

            Section {
                Toggle("Trip Reminders", isOn: $remindersEnabled)
            } footer: {
                Text("Get a local reminder shortly before an activity starts or a flight/transport departs.")
            }

            Section {
                NavigationLink {
                    VisitedPlacesMapView()
                } label: {
                    Label("My Travel Map", systemImage: "globe")
                }
            }

            Section {
                TextField("Full Name", text: $profile.fullName)
                    .textContentType(.name)
            } header: {
                Text("About You")
            } footer: {
                nameFooter
            }

            Section {
                NavigationLink("Privacy Policy") {
                    PrivacyPolicyView()
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(BrandPalette.canvas.ignoresSafeArea())
        .sheet(isPresented: $isPresentingSignIn) {
            SignInView()
        }
        .sheet(isPresented: $isShowingReauthPassword) {
            ReauthPasswordSheet { password in
                try await authService.reauthenticateWithPassword(password)
                await deleteAccount()
            }
        }
        .sheet(isPresented: $isShowingReauthApple) {
            ReauthAppleSheet { credential, rawNonce in
                try await authService.reauthenticateWithApple(credential: credential, rawNonce: rawNonce)
                await deleteAccount()
            }
        }
        .confirmationDialog(
            "Delete your account?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                Task { await deleteAccount() }
            }
        } message: {
            Text("This permanently deletes your account, removes you from every shared trip, and deletes any trips you own. This can't be undone.")
        }
        .alert("Couldn't Delete Account", isPresented: $isShowingDeleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteAccountErrorMessage)
        }
        .overlay {
            if isDeletingAccount {
                ProgressView()
            }
        }
        .onChange(of: remindersEnabled) { _, isOn in
            if isOn {
                NotificationScheduler.rescheduleAllReminders(trips: trips)
            } else {
                NotificationScheduler.cancelAllReminders()
            }
        }
        .task(id: authService.isSignedIn) {
            guard authService.isSignedIn, let uid = authService.firebaseUser?.uid else {
                appUserProfile = nil
                return
            }
            appUserProfile = try? await UserDirectoryService.fetchProfile(uid: uid)

            // First time here: start from the name the account already has,
            // unless that's just an email or the "Traveler" fallback.
            if profile.fullName.trimmingCharacters(in: .whitespaces).isEmpty,
               let name = appUserProfile?.displayName ?? authService.firebaseUser?.displayName,
               !name.contains("@"), name != "Traveler" {
                profile.fullName = name
            }
        }
        // Typing a name saves it to the account a moment after you stop, so it
        // becomes the name your travel companions see.
        .task(id: profile.fullName) {
            await syncNameIfNeeded()
        }
    }

    private enum NameSyncState: Equatable {
        case idle, saving, saved, failed(String)
    }

    @ViewBuilder
    private var nameFooter: some View {
        switch nameSyncState {
        case .saving:
            Text("Saving your name…")
        case .saved:
            Text("Saved. This is the name your travel companions see.")
        case .failed(let message):
            Text("Couldn't update your name: \(message)")
                .foregroundStyle(.red)
        case .idle:
            Text(authService.isSignedIn
                 ? "This is the name your travel companions see."
                 : "Sign in to share your name with the people you travel with.")
        }
    }

    private func syncNameIfNeeded() async {
        guard authService.isSignedIn, let user = authService.firebaseUser else {
            nameSyncState = .idle
            return
        }
        let name = profile.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != (appUserProfile?.displayName ?? user.displayName) else { return }

        // Wait for a pause in typing; the next keystroke cancels this task.
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }

        nameSyncState = .saving
        do {
            try await UserDirectoryService.updateDisplayName(name, for: user)
            appUserProfile = try? await UserDirectoryService.fetchProfile(uid: user.uid)
            nameSyncState = .saved
        } catch {
            nameSyncState = .failed(error.localizedDescription)
        }
    }

    @ViewBuilder
    private var accountSectionContent: some View {
        if authService.isSignedIn {
            VStack(alignment: .leading, spacing: 2) {
                Text(appUserProfile?.displayName ?? authService.firebaseUser?.displayName ?? "Signed in")
                    .font(AppFont.outfit(15, weight: .semibold, relativeTo: .body))
                if let email = appUserProfile?.email ?? authService.firebaseUser?.email {
                    Text(email)
                        .font(AppFont.outfit(12, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                }
            }
            Button("Sign Out", role: .destructive) {
                try? authService.signOut()
                appUserProfile = nil
            }
            Button("Delete Account", role: .destructive) {
                isShowingDeleteConfirmation = true
            }
            .disabled(isDeletingAccount)
        } else {
            Button {
                isPresentingSignIn = true
            } label: {
                HStack {
                    Text("Sign In")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
        }
    }

    /// If Firebase reports the session isn't fresh enough to delete the
    /// account, re-authenticates (silently via Google, or via a password
    /// prompt) and retries — `AuthService.deleteAccount()`'s own Firestore
    /// cleanup is idempotent, so repeating it here is harmless.
    private func deleteAccount() async {
        guard let uid = authService.firebaseUser?.uid else { return }
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        do {
            try await authService.deleteAccount()
            for trip in trips where trip.ownerUID == uid {
                modelContext.delete(trip)
            }
            appUserProfile = nil
        } catch AuthServiceError.requiresRecentLogin {
            switch authService.signInProviderID {
            case "google.com":
                await reauthenticateWithGoogleThenRetryDelete()
            case "apple.com":
                isShowingReauthApple = true
            default:
                isShowingReauthPassword = true
            }
        } catch {
            deleteAccountErrorMessage = error.localizedDescription
            isShowingDeleteError = true
        }
    }

    private func reauthenticateWithGoogleThenRetryDelete() async {
        do {
            try await authService.reauthenticateWithGoogle()
            await deleteAccount()
        } catch {
            deleteAccountErrorMessage = error.localizedDescription
            isShowingDeleteError = true
        }
    }
}

/// Password re-entry for email/password accounts when Firebase requires a
/// fresher session before it will delete the account (see
/// `AuthService.deleteAccount()`). Owns its own submit/error/loading state
/// so a wrong password just shows an inline error without dismissing.
private struct ReauthPasswordSheet: View {
    var onSubmit: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Enter your password to confirm account deletion.")
                    .font(AppFont.outfit(14, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .modifier(GlassOrStickerCard(cornerRadius: AppRadius.denseCard))

                if let errorMessage {
                    Text(errorMessage)
                        .font(AppFont.outfit(12, relativeTo: .caption))
                        .foregroundStyle(Color.appDanger)
                        .multilineTextAlignment(.center)
                }

                Button("Delete Account", role: .destructive) {
                    Task { await submit() }
                }
                .buttonStyle(.appPrimary)
                .disabled(password.isEmpty || isSubmitting)

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
                if isSubmitting {
                    ProgressView()
                }
            }
        }
    }

    private func submit() async {
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await onSubmit(password)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Apple re-presentation for Apple-signed-in accounts when Firebase
/// requires a fresher session before it will delete the account — same
/// idea as `ReauthPasswordSheet`, just for the other sign-in method.
private struct ReauthAppleSheet: View {
    var onSubmit: (ASAuthorizationAppleIDCredential, String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.authorizationController) private var authorizationController
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Confirm with Apple to continue deleting your account.")
                    .font(AppFont.outfit(14, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)

                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        Image(systemName: "apple.logo")
                        Text("Continue with Apple")
                    }
                }
                .buttonStyle(.appSecondary)
                .disabled(isSubmitting)

                if let errorMessage {
                    Text(errorMessage)
                        .font(AppFont.outfit(12, relativeTo: .caption))
                        .foregroundStyle(Color.appDanger)
                        .multilineTextAlignment(.center)
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
                if isSubmitting {
                    ProgressView()
                }
            }
        }
    }

    private func submit() async {
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let nonce = AuthService.makeAppleSignInNonce()
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.nonce = nonce.hashed

            let result = try await authorizationController.performRequest(request)
            guard case .appleID(let credential) = result else {
                errorMessage = "Apple sign-in didn't return a usable credential."
                return
            }
            try await onSubmit(credential, nonce.raw)
            dismiss()
        } catch {
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
        }
    }
}
