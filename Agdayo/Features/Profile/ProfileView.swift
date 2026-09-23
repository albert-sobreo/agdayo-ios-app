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
    @Query private var trips: [Trip]
    @State private var appUserProfile: AppUserProfile?
    @State private var isPresentingSignIn = false
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
}
