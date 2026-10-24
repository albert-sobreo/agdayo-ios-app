import SwiftUI
import SwiftData
import FirebaseAuth

struct PollListView: View {
    let trip: Trip
    var memberProfiles: [AppUserProfile] = []

    /// Live query scoped to this trip rather than a `trip.polls` traversal —
    /// see `ItineraryTimelineView`'s equivalent property for why.
    @Query private var polls: [TripPoll]

    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var authService
    @State private var isAdding = false

    init(trip: Trip, memberProfiles: [AppUserProfile] = []) {
        self.trip = trip
        self.memberProfiles = memberProfiles
        let tripID = trip.id
        _polls = Query(filter: #Predicate<TripPoll> { $0.trip?.id == tripID }, sort: \TripPoll.createdAt, order: .reverse)
    }

    /// Votes are keyed by uid; a signed-out, unshared trip has a single local voter.
    private var currentUID: String { authService.firebaseUser?.uid ?? "local" }

    /// The owner decides votes. A trip that was never shared belongs to whoever holds it.
    private var isOwner: Bool {
        trip.ownerUID == nil || trip.ownerUID == authService.firebaseUser?.uid
    }

    private var openPolls: [TripPoll] { polls.filter { !$0.isClosed } }
    private var closedPolls: [TripPoll] { polls.filter(\.isClosed) }

    var body: some View {
        Group {
            if polls.isEmpty {
                EmptyStateView(
                    iconName: "chart.bar",
                    title: "No Polls Yet",
                    message: "Ask the group a question, or propose an activity for everyone to vote on.",
                    actionTitle: "Start a Poll",
                    action: { isAdding = true }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(BrandPalette.canvas.ignoresSafeArea())
            } else {
                List {
                    if !openPolls.isEmpty {
                        Section {
                            ForEach(openPolls) { poll in card(for: poll) }
                        } header: {
                            MoneySectionHeader(title: "Open", iconName: "checkmark.circle", accentColor: trip.theme.accentColor)
                        }
                    }
                    if !closedPolls.isEmpty {
                        Section {
                            ForEach(closedPolls) { poll in card(for: poll) }
                        } header: {
                            MoneySectionHeader(title: "Closed", iconName: "lock", accentColor: trip.theme.accentColor)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(BrandPalette.canvas.ignoresSafeArea())
            }
        }
        .navigationTitle("Polls")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isAdding = true } label: {
                    Label("Start a Poll", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            PollEditSheet(trip: trip)
        }
    }

    private func card(for poll: TripPoll) -> some View {
        PollCard(
            poll: poll,
            accentColor: trip.theme.accentColor,
            myVote: poll.votes[currentUID],
            memberCount: max(1, memberProfiles.count),
            creatorName: memberProfiles.first { $0.uid == poll.createdByUID }?.displayName,
            canManage: isOwner,
            canDelete: isOwner || poll.createdByUID == currentUID,
            onVote: { TripPollService.vote(poll, option: $0, uid: currentUID, in: trip) },
            onClose: { TripPollService.close(poll, in: trip) },
            onApprove: { TripPollService.approve(poll, in: trip, modelContext: modelContext) },
            onDelete: { TripPollService.delete(poll, in: trip, modelContext: modelContext) }
        )
        .moneyRow()
    }
}

/// One vote as a card: the question, each option as a tappable bar filled to
/// its share of the votes, and the owner's controls in a menu.
private struct PollCard: View {
    let poll: TripPoll
    let accentColor: Color
    let myVote: Int?
    let memberCount: Int
    let creatorName: String?
    let canManage: Bool
    let canDelete: Bool
    let onVote: (Int) -> Void
    let onClose: () -> Void
    let onApprove: () -> Void
    let onDelete: () -> Void

    @State private var isConfirmingDelete = false

    private var isProposal: Bool { poll.kind == .activityProposal }

    var body: some View {
        MoneyCard {
            VStack(alignment: .leading, spacing: 12) {
                header

                VStack(alignment: .leading, spacing: 4) {
                    Text(poll.question)
                        .font(AppFont.barlowCondensed(24, weight: .semibold))
                    if isProposal { proposalDetails }
                }

                VStack(spacing: 8) {
                    ForEach(poll.options.indices, id: \.self) { index in
                        optionRow(index)
                    }
                }

                footer
            }
        }
        .confirmationDialog("Delete this poll?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(isProposal ? "Activity" : "Poll", systemImage: isProposal ? poll.iconName : "chart.bar")
                .font(AppFont.outfit(11, weight: .semibold, relativeTo: .caption2))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(accentColor)
            if poll.isClosed {
                Text("Closed")
                    .font(AppFont.outfit(11, weight: .semibold, relativeTo: .caption2))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if (canManage && !poll.isClosed) || canDelete {
                Menu {
                    if canManage && !poll.isClosed {
                        if isProposal {
                            Button("Approve & Add to Itinerary", systemImage: "checkmark.circle", action: onApprove)
                        }
                        Button(isProposal ? "Close Without Adding" : "Close Vote", systemImage: "lock", action: onClose)
                    }
                    if canDelete {
                        Button("Delete", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Poll actions")
            }
        }
    }

    @ViewBuilder
    private var proposalDetails: some View {
        if let date = poll.proposedDate {
            Label(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()), systemImage: "clock")
                .font(AppFont.outfit(12, relativeTo: .caption))
                .foregroundStyle(.secondary)
        }
        if !poll.location.isEmpty {
            Label(poll.location, systemImage: "mappin")
                .font(AppFont.outfit(12, relativeTo: .caption))
                .foregroundStyle(.secondary)
        }
    }

    private func optionRow(_ index: Int) -> some View {
        let count = poll.voteCount(for: index)
        let share = poll.totalVotes == 0 ? 0 : Double(count) / Double(poll.totalVotes)
        let isMine = myVote == index
        let isWinner = poll.isClosed && poll.leadingOptionIndices.contains(index)

        return Button {
            onVote(index)
        } label: {
            ZStack(alignment: .leading) {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 10)
                        .fill(accentColor.opacity(isMine || isWinner ? 0.28 : 0.14))
                        .frame(width: geo.size.width * share)
                        .animation(.easeOut(duration: 0.25), value: share)
                }
                HStack(spacing: 8) {
                    Image(systemName: isMine ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isMine ? accentColor : Color.secondary)
                    Text(poll.options[index])
                        .font(AppFont.outfit(15, weight: isMine || isWinner ? .semibold : .regular, relativeTo: .body))
                        .foregroundStyle(.primary)
                    if isWinner {
                        Image(systemName: "crown.fill")
                            .font(.caption)
                            .foregroundStyle(accentColor)
                    }
                    Spacer(minLength: 8)
                    Text("\(count)")
                        .font(AppFont.barlowCondensed(18, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(poll.isClosed)
        .accessibilityLabel("\(poll.options[index]), \(count) vote\(count == 1 ? "" : "s")")
        .accessibilityValue(isMine ? "Your vote" : "")
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text("\(poll.totalVotes) of \(memberCount) voted")
            if let creatorName {
                Text("·")
                Text("by \(creatorName)")
            }
        }
        .font(AppFont.outfit(12, relativeTo: .caption))
        .foregroundStyle(.secondary)
    }
}
