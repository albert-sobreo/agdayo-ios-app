import SwiftUI

/// Self-contained in-app privacy policy — no external hosting dependency.
/// Kept in sync by hand with what the app actually does; update this
/// alongside any change to what data Agdayo collects, stores, or shares.
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 48)
                    .frame(maxWidth: .infinity, alignment: .center)

                Text("Last updated \(Self.lastUpdated)")
                    .font(AppFont.outfit(12, relativeTo: .caption))
                    .foregroundStyle(.secondary)

                PolicySection(title: "Overview") {
                    Text("Agdayo is a trip-planning app. This policy explains what information Agdayo collects, how it's used, and how you can delete it. Agdayo does not sell your data, run ads, or use any advertising or analytics tracking SDKs.")
                }

                PolicySection(title: "Account Information") {
                    Text("Signing in is optional — you can plan trips fully offline without an account. If you choose to sign in (with Google or email/password), Agdayo collects your email address, display name, and, if using Google, your Google profile photo. This is used only to identify you to trip members you invite and to sync your trips across devices.")
                }

                PolicySection(title: "Location") {
                    Text("Agdayo uses location in a few places, always with your explicit permission:\n\n• Destination and activity search — resolves place names you type into map coordinates. Your device's location is used only to bias search results toward nearby places.\n• Live trip location sharing (opt-in) — while a trip is open and you've enabled it, your coarse location (deliberately rounded to roughly 100 meters, foreground-only) is shared with that trip's other members so you can find each other. This stops the moment you leave the screen or turn it off.\n• Visited-places map — trip destinations you've entered are shown on a personal map of places you've been.\n\nAgdayo never tracks your location in the background.")
                }

                PolicySection(title: "Trip Content") {
                    Text("Activities, accommodations, budgets, preparation tasks, transport details, and notes you enter are stored on your device. If you share a trip with others (via an invite code), that trip's content is also stored in Agdayo's cloud database (Firebase/Firestore) so members can collaborate in real time. Trips you never share stay entirely on your device.")
                }

                PolicySection(title: "Calendar and Notifications") {
                    Text("If you choose to add an activity or transport booking to your device's Calendar, Agdayo requests Calendar access for that one action. Reminders for upcoming activities are scheduled as local notifications on your device only — Agdayo does not use push notifications and has no server that knows your notification schedule.")
                }

                PolicySection(title: "On-Device AI") {
                    Text("AI itinerary suggestions, where available, are generated entirely on your device using Apple's on-device Apple Intelligence models. Your trip details are not sent to Agdayo's servers or any third party for this feature.")
                }

                PolicySection(title: "Third-Party Services") {
                    Text("Agdayo relies on a small number of services to function:\n\n• Firebase (Google) — authentication and the cloud database used for shared trips.\n• Apple MapKit — place search, maps, and directions.\n• A currency-exchange-rate API — receives only currency codes (e.g. \"USD\", \"PHP\"), never any personal or trip data.\n\nNone of these are used for advertising.")
                }

                PolicySection(title: "Your Choices") {
                    Text("You can sign out at any time from Profile. You can permanently delete your account from Profile → Delete Account — this removes your account, deletes any trips you own, removes you from shared trips, and deletes your profile from Agdayo's servers. This can't be undone.")
                }

                PolicySection(title: "Children's Privacy") {
                    Text("Agdayo is not directed at children under 13, and does not knowingly collect information from them.")
                }

                PolicySection(title: "Changes to This Policy") {
                    Text("If what Agdayo collects or how it's used changes, this page will be updated and the \"Last updated\" date above will change accordingly.")
                }

                PolicySection(title: "Contact") {
                    Text("Questions about this policy or your data can be sent to janalbertsobreo@gmail.com.")
                }
            }
            .padding(20)
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static let lastUpdated: String = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 9, day: 25)) ?? .now)
    }()
}

private struct PolicySection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppFont.outfit(16, weight: .semibold, relativeTo: .headline))
            content
                .font(AppFont.outfit(14, relativeTo: .body))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}
