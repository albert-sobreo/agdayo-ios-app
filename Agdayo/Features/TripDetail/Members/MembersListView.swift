import SwiftUI
import SwiftData
import FirebaseAuth

struct MembersListView: View {
    let trip: Trip
    let syncCoordinator: TripContentSyncCoordinator

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var authService

    @State private var isShowingShareSheet = false
    @State private var isShowingSignIn = false
    @State private var isShowingLeaveConfirmation = false
    @State private var joinCode: String = ""
    @State private var hasCopiedCode = false

    private var currentUID: String? {
        authService.firebaseUser?.uid
    }

    private var isCurrentUserOwner: Bool {
        guard let currentUID else { return false }
        return trip.ownerUID == currentUID
    }

    var body: some View {
        List {
            // Unauthenticated / Local-only Banner
            if !authService.isSignedIn || trip.ownerUID == nil {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "person.badge.shield.checkmark.fill")
                                .font(.title2)
                                .foregroundStyle(trip.theme.accentColor)
                            Text("Sign In to Collaborate")
                                .font(AppFont.outfit(16, weight: .bold, relativeTo: .headline))
                        }
                        Text("Sign in to invite friends with a shareable code and plan this trip together in real-time.")
                            .font(AppFont.outfit(13, relativeTo: .subheadline))
                            .foregroundStyle(.secondary)

                        Button {
                            isShowingSignIn = true
                        } label: {
                            Text("Sign In")
                                .font(AppFont.outfit(14, weight: .semibold, relativeTo: .subheadline))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(trip.theme.accentColor)
                    }
                    .padding(.vertical, 6)
                }
            } else {
                // Quick Invite Code Card
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("TRIP INVITE CODE")
                                    .font(AppFont.outfit(11, weight: .bold, relativeTo: .caption2))
                                    .tracking(1.2)
                                    .foregroundStyle(.secondary)

                                if joinCode.isEmpty {
                                    ProgressView()
                                        .frame(height: 28)
                                } else {
                                    Text(joinCode)
                                        .font(AppFont.outfit(24, weight: .bold, relativeTo: .title3))
                                        .monospaced()
                                        .foregroundStyle(trip.theme.accentColor)
                                }
                            }

                            Spacer()

                            if !joinCode.isEmpty {
                                Button {
                                    UIPasteboard.general.string = joinCode
                                    hasCopiedCode = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        hasCopiedCode = false
                                    }
                                } label: {
                                    Image(systemName: hasCopiedCode ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(hasCopiedCode ? .green : trip.theme.accentColor)
                                        .padding(10)
                                        .background(trip.theme.lightTintColor)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Copy invite code")
                            }

                            Button {
                                isShowingShareSheet = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Invite")
                                }
                                .font(AppFont.outfit(13, weight: .bold, relativeTo: .caption))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(trip.theme.accentColor)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }

                        Text("Anyone with this code can join and view/edit this trip.")
                            .font(AppFont.outfit(12, relativeTo: .caption))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            // Members List Section
            Section {
                let records = syncCoordinator.memberRecords
                if records.isEmpty {
                    // Fallback when syncCoordinator hasn't populated yet or offline
                    HStack(spacing: 12) {
                        Circle()
                            .fill(trip.theme.accentColor)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Text(String(authService.firebaseUser?.displayName?.first ?? "Y").uppercased())
                                    .font(AppFont.outfit(16, weight: .bold, relativeTo: .body))
                                    .foregroundStyle(.white)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(authService.firebaseUser?.displayName ?? "Trip Creator")
                                .font(AppFont.outfit(15, weight: .semibold, relativeTo: .body))
                            if let email = authService.firebaseUser?.email {
                                Text(email)
                                    .font(AppFont.outfit(12, relativeTo: .caption))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("Owner")
                            .font(AppFont.outfit(11, weight: .bold, relativeTo: .caption2))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(trip.theme.lightTintColor)
                            .foregroundStyle(trip.theme.accentColor)
                            .clipShape(Capsule())
                    }
                    .padding(.vertical, 4)
                } else {
                    ForEach(records) { member in
                        MemberRowView(
                            member: member,
                            theme: trip.theme,
                            canRemove: isCurrentUserOwner && !member.isOwner,
                            isCurrentUser: member.profile.uid == currentUID,
                            onRemove: {
                                removeMember(member)
                            }
                        )
                    }
                }
            } header: {
                Text("Members (\(max(1, syncCoordinator.memberRecords.count)))")
                    .font(AppFont.outfit(12, weight: .bold, relativeTo: .caption))
            } footer: {
                Text("All members have permission to view, add, and update activities, budget, accommodations, and notes.")
                    .font(AppFont.outfit(11, relativeTo: .caption2))
                    .foregroundStyle(.secondary)
            }

            // Leave Trip (for non-owners)
            if authService.isSignedIn && !isCurrentUserOwner && trip.ownerUID != nil {
                Section {
                    Button(role: .destructive) {
                        isShowingLeaveConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Leave Trip")
                                .font(AppFont.outfit(15, weight: .semibold, relativeTo: .body))
                            Spacer()
                        }
                    }
                }
            }
        }
        .navigationTitle("Members")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share Trip")
                .disabled(!authService.isSignedIn || trip.ownerUID == nil)
            }
        }
        .sheet(isPresented: $isShowingShareSheet) {
            TripShareSheet(trip: trip)
        }
        .sheet(isPresented: $isShowingSignIn) {
            SignInView()
        }
        .confirmationDialog(
            "Leave this trip?",
            isPresented: $isShowingLeaveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Leave Trip", role: .destructive) {
                leaveTrip()
            }
        } message: {
            Text("You will lose access to this trip and its itinerary.")
        }
        .task {
            await loadJoinCode()
        }
    }

    private func loadJoinCode() async {
        guard authService.isSignedIn, trip.ownerUID != nil else { return }
        if let existing = syncCoordinator.currentJoinCode, !existing.isEmpty {
            joinCode = existing
            return
        }
        if let code = try? await TripMembershipService.getOrCreateJoinCode(for: trip.id) {
            joinCode = code
        }
    }

    private func removeMember(_ member: TripMemberRecord) {
        let tripID = trip.id
        let uid = member.profile.uid
        Task {
            try? await TripMembershipService.removeMember(tripID: tripID, uid: uid)
        }
    }

    private func leaveTrip() {
        guard let currentUID else { return }
        let tripID = trip.id
        Task {
            try? await TripMembershipService.removeMember(tripID: tripID, uid: currentUID)
        }
        modelContext.delete(trip)
        dismiss()
    }
}
