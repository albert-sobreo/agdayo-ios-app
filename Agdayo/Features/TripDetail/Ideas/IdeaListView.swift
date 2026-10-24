import SwiftUI
import SwiftData
import FirebaseAuth

struct IdeaListView: View {
    let trip: Trip
    var memberProfiles: [AppUserProfile] = []

    /// Live query scoped to this trip rather than a `trip.ideas` traversal —
    /// see `ItineraryTimelineView`'s equivalent property for why.
    @Query private var ideas: [TripIdea]

    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var authService
    @State private var isAdding = false
    @State private var editingIdea: TripIdea?
    @State private var isShowingSignInAlert = false
    @State private var approvedActivity: Activity?

    init(trip: Trip, memberProfiles: [AppUserProfile] = []) {
        self.trip = trip
        self.memberProfiles = memberProfiles
        let tripID = trip.id
        _ideas = Query(filter: #Predicate<TripIdea> { $0.trip?.id == tripID }, sort: \TripIdea.createdAt, order: .reverse)
    }

    /// Likes are keyed by uid; a signed-out, unshared trip has a single local member.
    private var currentUID: String { authService.firebaseUser?.uid ?? "local" }

    /// The owner approves ideas. A trip that was never shared belongs to whoever holds it.
    private var isOwner: Bool {
        trip.ownerUID == nil || trip.ownerUID == authService.firebaseUser?.uid
    }

    /// A shared trip's ideas live in Firestore under your account, so adding or
    /// reacting while signed out would only ever be saved on this device.
    private var canParticipate: Bool {
        trip.ownerUID == nil || authService.firebaseUser != nil
    }

    /// Current members, so likes from people who left aren't counted. Unknown
    /// (nil) until the member list loads, and for unshared trips.
    private var eligibleVoters: Set<String>? {
        memberProfiles.isEmpty ? nil : Set(memberProfiles.map(\.uid))
    }

    /// Most-liked first, then newest.
    private var openIdeas: [TripIdea] {
        ideas.filter { !$0.isPlanned }.sorted {
            let (a, b) = ($0.likeCount(among: eligibleVoters), $1.likeCount(among: eligibleVoters))
            return a != b ? a > b : $0.createdAt > $1.createdAt
        }
    }

    private var plannedIdeas: [TripIdea] { ideas.filter(\.isPlanned) }

    private func startAdding() {
        if canParticipate { isAdding = true } else { isShowingSignInAlert = true }
    }

    var body: some View {
        Group {
            if ideas.isEmpty {
                EmptyStateView(
                    iconName: "lightbulb",
                    title: "No Ideas Yet",
                    message: "Save places and things the group wants to do. Everyone can add and 👍 them, and the trip owner can approve the ones that make the itinerary.",
                    actionTitle: "Add an Idea",
                    action: startAdding
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(BrandPalette.canvas.ignoresSafeArea())
            } else {
                List {
                    if !openIdeas.isEmpty {
                        Section {
                            ForEach(openIdeas) { idea in card(for: idea) }
                        } header: {
                            MoneySectionHeader(title: "Ideas", iconName: "lightbulb", accentColor: trip.theme.accentColor)
                        }
                    }
                    if !plannedIdeas.isEmpty {
                        Section {
                            ForEach(plannedIdeas) { idea in card(for: idea) }
                        } header: {
                            MoneySectionHeader(title: "Planned", iconName: "checkmark.circle", accentColor: trip.theme.accentColor)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(BrandPalette.canvas.ignoresSafeArea())
            }
        }
        .navigationTitle("Ideas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: startAdding) {
                    Label("Add Idea", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            IdeaEditSheet(trip: trip)
        }
        .sheet(item: $editingIdea) { idea in
            IdeaEditSheet(trip: trip, editingIdea: idea)
        }
        .alert("Sign In to Add Ideas", isPresented: $isShowingSignInAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This trip is shared, so you need to be signed in to add, edit or react to ideas.")
        }
        .alert("Added to Itinerary", isPresented: Binding(get: { approvedActivity != nil }, set: { if !$0 { approvedActivity = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            if let approvedActivity {
                Text("\(approvedActivity.title) is on \(approvedActivity.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())). Change the time from the itinerary.")
            }
        }
    }

    private func card(for idea: TripIdea) -> some View {
        let canEdit = isOwner || idea.addedByUID == currentUID
        return IdeaCard(
            idea: idea,
            accentColor: trip.theme.accentColor,
            isLikedByMe: idea.likedBy.contains(currentUID),
            likeCount: idea.likeCount(among: eligibleVoters),
            addedByName: memberProfiles.first { $0.uid == idea.addedByUID }?.displayName,
            canApprove: isOwner,
            canEdit: canEdit,
            onLike: {
                guard canParticipate else {
                    isShowingSignInAlert = true
                    return
                }
                TripIdeaService.toggleLike(idea, uid: currentUID, in: trip)
            },
            onApprove: { approvedActivity = TripIdeaService.approve(idea, in: trip, modelContext: modelContext) },
            onEdit: {
                if canParticipate { editingIdea = idea } else { isShowingSignInAlert = true }
            },
            onDelete: { TripIdeaService.delete(idea, in: trip, modelContext: modelContext) }
        )
        .moneyRow()
    }
}

/// One idea as a card: title, place and note, a 👍 with its count, and a menu.
private struct IdeaCard: View {
    let idea: TripIdea
    let accentColor: Color
    let isLikedByMe: Bool
    let likeCount: Int
    let addedByName: String?
    let canApprove: Bool
    let canEdit: Bool
    let onLike: () -> Void
    let onApprove: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isConfirmingDelete = false

    var body: some View {
        MoneyCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Text(idea.title)
                        .font(AppFont.barlowCondensed(24, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if idea.isPlanned {
                        Label("Planned", systemImage: "checkmark.circle.fill")
                            .font(AppFont.outfit(11, weight: .semibold, relativeTo: .caption2))
                            .textCase(.uppercase)
                            .foregroundStyle(accentColor)
                    }
                    if (canApprove && !idea.isPlanned) || canEdit {
                        menu
                    }
                }

                if !idea.location.isEmpty {
                    Label(idea.location, systemImage: "mappin")
                        .font(AppFont.outfit(12, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                }
                if !idea.note.isEmpty {
                    Text(idea.note)
                        .font(AppFont.outfit(14, relativeTo: .subheadline))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
                if let url = idea.linkURL {
                    Link(destination: url) {
                        Label(url.host() ?? "Link", systemImage: "link")
                            .font(AppFont.outfit(12, weight: .medium, relativeTo: .caption))
                            .foregroundStyle(accentColor)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 10) {
                    Button(action: onLike) {
                        HStack(spacing: 6) {
                            Image(systemName: isLikedByMe ? "hand.thumbsup.fill" : "hand.thumbsup")
                            Text("\(likeCount)")
                                .font(AppFont.barlowCondensed(18, weight: .semibold))
                        }
                        .foregroundStyle(isLikedByMe ? accentColor : Color.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isLikedByMe ? accentColor.opacity(0.15) : Color(.secondarySystemFill), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isLikedByMe ? "Remove your thumbs up" : "Thumbs up")
                    .accessibilityValue("\(likeCount)")

                    if let addedByName {
                        Text("by \(addedByName)")
                            .font(AppFont.outfit(12, relativeTo: .caption))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .confirmationDialog("Delete this idea?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private var menu: some View {
        Menu {
            if canApprove && !idea.isPlanned {
                Button("Approve & Add to Itinerary", systemImage: "checkmark.circle", action: onApprove)
            }
            if canEdit {
                Button("Edit", systemImage: "pencil", action: onEdit)
                Button("Delete", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Idea actions")
    }
}
