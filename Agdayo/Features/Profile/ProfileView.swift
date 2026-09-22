import SwiftUI
import SwiftData

/// Local-only personalization profile — no accounts, no sync. A singleton
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

    var body: some View {
        Form {
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
