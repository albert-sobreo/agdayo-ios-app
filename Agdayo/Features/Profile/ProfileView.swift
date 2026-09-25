import SwiftUI
import SwiftData
import FirebaseAuth

/// The local preferences form (fullName/homeRegion/vacation types) is
/// unrelated to the account below — it stays local-only regardless of
/// sign-in state. A singleton UserProfile row is lazily created on first
/// appear if none exists yet.
struct ProfileView: View {
    @Query private var profiles: [UserProfile]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if let profile = profiles.first {
                ProfileForm(profile: profile)
            } else {
                ProgressView()
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
    @State private var isDeletingAccount = false
    @State private var isShowingDeleteError = false
    @State private var deleteAccountErrorMessage = ""
    @AppStorage(NotificationScheduler.remindersEnabledKey) private var remindersEnabled = true

    var body: some View {
        Form {
            Section("Account") {
                accountSectionContent
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

            Section("About You") {
                TextField("Full Name", text: $profile.fullName)
                TextField("Home Region", text: $profile.homeRegion)
                Toggle("I have travel experience", isOn: $profile.hasTravelExperience)
            }

            Section("Preferred Vacation Types") {
                ForEach(VacationType.allCases) { type in
                    Button {
                        toggle(type)
                    } label: {
                        HStack {
                            Text(type.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if profile.preferredVacationTypes.contains(type) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.appPrimary)
                            }
                        }
                    }
                }
            }

            Section {
                Text("Stored only on this device. Used to personalize AI trip suggestions.")
                    .font(AppFont.outfit(12, relativeTo: .caption))
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $isPresentingSignIn) {
            SignInView()
        }
        .sheet(isPresented: $isShowingReauthPassword) {
            ReauthPasswordSheet { password in
                try await authService.reauthenticateWithPassword(password)
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

    private func toggle(_ type: VacationType) {
        if let index = profile.preferredVacationTypes.firstIndex(of: type) {
            profile.preferredVacationTypes.remove(at: index)
        } else {
            profile.preferredVacationTypes.append(type)
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
            if authService.signInProviderID == "google.com" {
                await reauthenticateWithGoogleThenRetryDelete()
            } else {
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
