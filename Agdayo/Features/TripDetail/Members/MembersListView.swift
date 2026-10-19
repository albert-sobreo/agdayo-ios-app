import SwiftUI
import SwiftData
import FirebaseAuth

struct MembersListView: View {
    let trip: Trip
    let syncCoordinator: TripContentSyncCoordinator
    var onLeftTrip: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
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
                    MoneyCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                MoneyIconBadge(systemName: "person.badge.shield.checkmark.fill", accentColor: trip.theme.accentColor)
                                Text("Sign in to collaborate")
                                    .font(AppFont.barlowCondensed(24, weight: .semibold))
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
                    }
                    .moneyRow()
                }
            } else {
                // Quick Invite Code Card
                Section {
                    MoneyCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("TRIP INVITE CODE")
                                .font(AppFont.outfit(11, weight: .semibold, relativeTo: .caption2))
                                .tracking(1.5)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 10) {
                                if joinCode.isEmpty {
                                    ProgressView()
                                        .frame(height: 40)
                                } else {
                                    Text(joinCode)
                                        .font(AppFont.barlowCondensed(40, weight: .semibold))
                                        .tracking(4)
                                        .foregroundStyle(trip.theme.accentColor)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.6)
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
                                            .frame(width: 40, height: 40)
                                            .background(trip.theme.accentColor.opacity(0.14), in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Copy invite code")
                                }

                                Button {
                                    isShowingShareSheet = true
                                } label: {
                                    Label("Invite", systemImage: "square.and.arrow.up")
                                        .font(AppFont.outfit(13, weight: .bold, relativeTo: .caption))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(trip.theme.accentColor, in: Capsule())
                                        .foregroundStyle(.white)
                                }
                                .buttonStyle(.plain)
                            }

                            Text("Anyone with this code can join and view/edit this trip.")
                                .font(AppFont.outfit(12, relativeTo: .caption))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .moneyRow()
                }
            }

            // Members List Section
            Section {
                let records = syncCoordinator.memberRecords
                if records.isEmpty {
                    // Fallback when syncCoordinator hasn't populated yet or offline
                    MoneyCard(padding: 14) {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(trip.theme.accentColor)
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Text(String(authService.firebaseUser?.displayName?.first ?? "Y").uppercased())
                                        .font(AppFont.outfit(16, weight: .bold, relativeTo: .body))
                                        .foregroundStyle(.white)
                                )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(authService.firebaseUser?.displayName ?? "Trip Creator")
                                    .font(AppFont.outfit(16, weight: .semibold, relativeTo: .body))
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
                                .background(trip.theme.accentColor.opacity(0.15), in: Capsule())
                                .foregroundStyle(trip.theme.accentColor)
                        }
                    }
                    .moneyRow()
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
                        .moneyRow()
                    }
                }

                // A row rather than a footer: a plain list draws footers on a white background.
                Text("All members have permission to view, add, and update activities, budget, accommodations, and notes.")
                    .font(AppFont.outfit(11, relativeTo: .caption2))
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 8, trailing: 20))
            } header: {
                HStack {
                    MoneySectionHeader(title: "Members", iconName: "person.2", accentColor: trip.theme.accentColor)
                    Text("\(max(1, syncCoordinator.memberRecords.count))")
                        .font(AppFont.barlowCondensed(20, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            // Leave Trip (for non-owners)
            if authService.isSignedIn && !isCurrentUserOwner && trip.ownerUID != nil {
                Section {
                    Button(role: .destructive) {
                        isShowingLeaveConfirmation = true
                    } label: {
                        MoneyCard(padding: 14) {
                            Label("Leave Trip", systemImage: "rectangle.portrait.and.arrow.right")
                                .font(AppFont.outfit(15, weight: .semibold, relativeTo: .body))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .moneyRow()
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(BrandPalette.canvas.ignoresSafeArea())
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
        NotificationScheduler.cancelReminders(for: trip)
        modelContext.delete(trip)
        // Pops all the way back to the trip list instead of `dismiss()`,
        // which would only pop one level back to the (now-deleted) trip's
        // own detail screen.
        onLeftTrip()
    }
}
