import SwiftUI
import SwiftData
import FirebaseAuth

struct TripDetailView: View {
    let trip: Trip
    var onLeftTrip: () -> Void = {}

    /// Live queries scoped to this trip rather than relationship traversals
    /// (`trip.activities.count`, `trip.planningProgress`, etc.) — see
    /// `ItineraryTimelineView`'s equivalent property for why those don't
    /// reliably refresh live when a child screen inserts a new item.
    @Query private var activities: [Activity]
    @Query private var accommodations: [Accommodation]
    @Query private var budgetCategories: [BudgetCategory]
    @Query private var preparationTasks: [PreparationTask]
    @Query private var transportSegments: [TransportSegment]
    @Query private var dayNotes: [DayNote]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var authService
    @Environment(TripLiveActivityCoordinator.self) private var liveActivity
    @State private var isShowingMap = false
    @State private var isShowingSettings = false
    @State private var isShowingShareSheet = false
    @State private var syncCoordinator = TripContentSyncCoordinator()

    init(trip: Trip, onLeftTrip: @escaping () -> Void = {}) {
        self.trip = trip
        self.onLeftTrip = onLeftTrip
        let tripID = trip.id
        _activities = Query(filter: #Predicate<Activity> { $0.trip?.id == tripID })
        _accommodations = Query(filter: #Predicate<Accommodation> { $0.trip?.id == tripID })
        _budgetCategories = Query(filter: #Predicate<BudgetCategory> { $0.trip?.id == tripID })
        _preparationTasks = Query(filter: #Predicate<PreparationTask> { $0.trip?.id == tripID })
        _transportSegments = Query(filter: #Predicate<TransportSegment> { $0.trip?.id == tripID })
        _dayNotes = Query(filter: #Predicate<DayNote> { $0.trip?.id == tripID })
    }

    /// Same conversion `Trip.activityCostsTotal` does, just against the
    /// locally-queried `activities` instead of the relationship traversal.
    private var activityCostsTotal: Double {
        activities.reduce(0) { $0 + ($1.costAndRate(inTripCurrency: trip.currency)?.cost ?? 0) }
    }

    private var accommodationCostsTotal: Double {
        accommodations.reduce(0) { $0 + $1.totalCost }
    }

    private var transportCostsTotal: Double {
        transportSegments.reduce(0) { $0 + ($1.costAndRate(inTripCurrency: trip.currency)?.cost ?? 0) }
    }

    /// Money actually committed — categories are planned budget, not an
    /// expense (see `Trip.actualSpentTotal`).
    private var actualSpentTotal: Double {
        activityCostsTotal + accommodationCostsTotal + transportCostsTotal
    }

    /// Same idea as `Trip.planningProgress`, against the local queries.
    private var planningProgress: (completed: Int, total: Int) {
        let sections = [
            !activities.isEmpty,
            !budgetCategories.isEmpty,
            !accommodations.isEmpty,
            !preparationTasks.isEmpty,
            !transportSegments.isEmpty,
        ]
        return (sections.filter { $0 }.count, sections.count)
    }

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
                    planningProgress: planningProgress,
                    members: syncCoordinator.memberProfiles,
                    isLiveActivityRunning: liveActivity.isRunning(tripID: trip.id),
                    onViewMap: { isShowingMap = true },
                    onSettings: { isShowingSettings = true },
                    onInvite: { isShowingShareSheet = true }
                )

                TripSectionsRow(
                    accentColor: trip.theme.accentColor,
                    activityCount: activities.count,
                    accommodationCount: accommodations.count,
                    actualSpentTotal: actualSpentTotal,
                    overallBudget: trip.overallBudget,
                    currency: trip.currency,
                    taskCount: preparationTasks.count,
                    transportCount: transportSegments.count,
                    noteCount: dayNotes.count,
                    memberCount: max(1, syncCoordinator.memberProfiles.count),
                    showsBalances: syncCoordinator.memberProfiles.count > 1
                )
                ItineraryTimelineView(trip: trip, memberProfiles: syncCoordinator.memberProfiles, isEmbedded: true)
            }
            .padding(.bottom, 24)
        }
        .background(BrandPalette.canvas.ignoresSafeArea())
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
        .task {
            // Opportunistic refresh — see `TripLiveActivityCoordinator`'s
            // doc comment on why there's no push to do this in the
            // background. No-ops if this trip's Live Activity isn't running.
            liveActivity.refresh(trip: trip, activities: activities)
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
            ItineraryTimelineView(trip: trip, memberProfiles: syncCoordinator.memberProfiles)
        case .accommodations:
            AccommodationListView(trip: trip, memberProfiles: syncCoordinator.memberProfiles)
        case .budget:
            BudgetOverviewView(trip: trip, memberProfiles: syncCoordinator.memberProfiles)
        case .balances:
            BalancesView(trip: trip, memberProfiles: syncCoordinator.memberProfiles)
        case .preparation:
            PreparationChecklistView(trip: trip)
        case .transport:
            TransportSegmentListView(trip: trip, memberProfiles: syncCoordinator.memberProfiles)
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
                    .font(AppFont.outfit(15, relativeTo: .subheadline))
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
                    .font(AppFont.outfit(15, weight: .medium, relativeTo: .subheadline))
                if !location.isEmpty {
                    Text(location)
                        .font(AppFont.outfit(12, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(date, format: .dateTime.hour().minute())
                .font(AppFont.outfit(12, relativeTo: .caption))
                .foregroundStyle(.secondary)
        }
    }
}
