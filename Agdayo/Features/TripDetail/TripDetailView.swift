import SwiftUI
import SwiftData
import FirebaseAuth

struct TripDetailView: View {
    let trip: Trip
    var onLeftTrip: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var authService
    @State private var isShowingMap = false
    @State private var isShowingSettings = false
    @State private var isShowingShareSheet = false
    @State private var syncCoordinator = TripContentSyncCoordinator()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TripHeaderView(
                    name: trip.name,
                    location: trip.location,
                    startDate: trip.startDate,
                    endDate: trip.endDate,
                    theme: trip.theme,
                    status: trip.status,
                    planningProgress: trip.planningProgress,
                    members: syncCoordinator.memberProfiles,
                    onViewMap: { isShowingMap = true },
                    onSettings: { isShowingSettings = true }
                )

                TripSectionsRow(
                    accentColor: trip.theme.accentColor,
                    activityCount: trip.activities.count,
                    accommodationCount: trip.accommodations.count,
                    budgetedTotal: trip.budgetedTotal,
                    overallBudget: trip.overallBudget,
                    currency: trip.currency,
                    taskCount: trip.preparationTasks.count,
                    transportCount: trip.transportSegments.count,
                    noteCount: trip.dayNotes.count,
                    memberCount: max(1, syncCoordinator.memberProfiles.count)
                )

                UpcomingActivitiesPreview(trip: trip)
                    .padding(.horizontal)
            }
            .padding(.bottom, 24)
        }
        .background {
            Image("light-bg")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share Trip")
            }
        }
        .navigationDestination(for: TripSectionRoute.self) { route in
            destination(for: route)
        }
        .sheet(isPresented: $isShowingMap) {
            NavigationStack {
                TripMapView(trip: trip)
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            TripSettingsView(trip: trip, onDeleted: deleteTrip)
        }
        .sheet(isPresented: $isShowingShareSheet) {
            TripShareSheet(trip: trip)
        }
        .task {
            // Must finish (or fail) before starting the listeners below —
            // racing them meant the listeners could attach (and permanently
            // fail, since `start()` no-ops on a second attempt) before this
            // self-heal had actually created the membership doc.
            guard let ownerUID = trip.ownerUID, authService.isSignedIn else { return }
            if let uid = authService.firebaseUser?.uid {
                let role = uid == ownerUID ? "owner" : "member"
                try? await TripMembershipService.ensureMembership(tripID: trip.id, uid: uid, role: role)
            }
            syncCoordinator.start(for: trip, modelContext: modelContext)
        }
        // Deliberately no `.onDisappear { syncCoordinator.stop() }` — this
        // view stays the root of `Members`/`Itinerary`/etc. while those are
        // pushed on top of it, so stopping here tore down the listeners
        // (and wiped member data) while a child screen was still showing it.
        // The coordinator is torn down naturally when this screen is
        // actually popped and its `@State` is released.
    }

    @ViewBuilder
    private func destination(for route: TripSectionRoute) -> some View {
        switch route {
        case .itinerary:
            ItineraryTimelineView(trip: trip)
        case .accommodations:
            AccommodationListView(trip: trip)
        case .budget:
            BudgetOverviewView(trip: trip)
        case .preparation:
            PreparationChecklistView(trip: trip)
        case .transport:
            TransportSegmentListView(trip: trip)
        case .notes:
            DayNoteListView(trip: trip)
        case .members:
            MembersListView(trip: trip, syncCoordinator: syncCoordinator, onLeftTrip: onLeftTrip)
        }
    }

    private func deleteTrip() {
        if trip.ownerUID != nil {
            let tripID = trip.id
            Task {
                try? await TripMembershipService.deleteTripRecord(tripID: tripID)
            }
        }
        modelContext.delete(trip)
        isShowingSettings = false
        dismiss()
    }
}

private struct UpcomingActivitiesPreview: View {
    let trip: Trip

    private var upcoming: [Activity] {
        trip.activities.sorted { $0.date < $1.date }.prefix(3).map { $0 }
    }

    var body: some View {
        SectionCard(title: "Upcoming Activities") {
            if upcoming.isEmpty {
                Text("No activities yet. Add one from the Itinerary section.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(upcoming) { activity in
                        UpcomingActivityRow(title: activity.title, location: activity.location, date: activity.date, iconName: activity.iconName)
                    }
                }
            }
        }
    }
}

private struct UpcomingActivityRow: View {
    let title: String
    let location: String
    let date: Date
    let iconName: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                if !location.isEmpty {
                    Text(location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(date, format: .dateTime.hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
