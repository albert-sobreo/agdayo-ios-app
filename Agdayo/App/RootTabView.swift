import SwiftUI
import SwiftData
import FirebaseAuth

private enum RootTab: Hashable {
    case home
    case trips
    case map
    case profile
}

struct RootTabView: View {
    @Query private var trips: [Trip]
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var authService
    @Environment(LiveLocationSharingCoordinator.self) private var locationSharing
    @Environment(TripLiveActivityCoordinator.self) private var liveActivity
    @Environment(\.scenePhase) private var scenePhase

    @State private var deepLinkCode: String = ""
    @State private var isPresentingDeepLinkJoin = false
    @State private var pendingJoinedTrip: Trip?
    @State private var selectedTab: RootTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house.fill", value: .home) {
                HomeView()
            }
            Tab("Trips", systemImage: "suitcase.fill", value: .trips) {
                TripListView(pendingJoinedTrip: $pendingJoinedTrip)
            }
            Tab("Map", systemImage: "map.fill", value: .map) {
                NavigationStack {
                    // Leaving a trip from here should land on the trips
                    // list, not just this tab's own map root.
                    GlobalMapView(onLeftTrip: { selectedTab = .trips })
                        .background(BackgroundImageModifier())
                }
            }
            Tab("Profile", systemImage: "person.crop.circle", value: .profile) {
                NavigationStack {
                    ProfileView()
                        .background(BackgroundImageModifier())
                }
            }
        }
        .tint(.appPrimary)
        // Sits above the TabView (and whatever's pushed inside any tab's own
        // NavigationStack) so the indicator stays visible while browsing a
        // trip's Itinerary/Budget/etc, not just its Map screen.
        .overlay(alignment: .bottom) {
            if locationSharing.isSharing {
                LiveSharingBanner(
                    tripName: locationSharing.sharingTrip?.name ?? "Trip",
                    onStop: { locationSharing.stop() }
                )
                .padding(.bottom, 60)
            }
        }
        .onOpenURL { url in
            if url.scheme == "agdayo" && url.host == "join" {
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let code = components.queryItems?.first(where: { $0.name.lowercased() == "code" })?.value {
                    deepLinkCode = code
                }
                isPresentingDeepLinkJoin = true
            }
        }
        .sheet(isPresented: $isPresentingDeepLinkJoin) {
            JoinTripSheet(initialCode: deepLinkCode, onJoined: { trip in
                // Redirect logic lives on the Trips tab's own NavigationPath
                // (see TripListView) — switch there so the join is visible
                // regardless of which tab (now possibly Home) was active.
                selectedTab = .trips
                pendingJoinedTrip = trip
            })
        }
        .task {
            NotificationScheduler.requestAuthorizationIfNeeded()
        }
        .task(id: authService.isSignedIn) {
            // The full field-by-field refresh (1 read per owned trip) only
            // runs here, on a sign-in-state change — not on every
            // foreground. Realtime listeners already keep an *open* trip's
            // fields live, and `TripListView`'s pull-to-refresh covers the
            // "did something change while I was away" case on demand, so a
            // per-trip poll on every single foreground would just be
            // redundant read volume that scales with trip count.
            backfillOwnershipIfNeeded()
            if let uid = authService.firebaseUser?.uid {
                await TripDiscoveryService.refreshMemberTrips(uid: uid, localTrips: trips, modelContext: modelContext)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Only retries trips that failed to upload earlier (no network,
            // or created while signed out) — a no-op loop once everything
            // has synced, so it's cheap to run on every foreground.
            if newPhase == .active {
                backfillOwnershipIfNeeded()
                // Live Activities have no push server to refresh them in
                // the background, so every foreground is the opportunity
                // to bring the current/next-activity state up to date (and
                // to restart one that expired under the system's 8h/12h
                // cap while the trip is still active).
                if let runningTripID = liveActivity.runningTripID {
                    if let trip = trips.first(where: { $0.id == runningTripID }), trip.status == .active {
                        liveActivity.reconcile(trip: trip, activities: trip.activities)
                    } else {
                        liveActivity.stop()
                    }
                }
            }
            // Live sharing is deliberately foreground-only (see
            // `LiveLocationSharingCoordinator`) — stop broadcasting the
            // moment the app actually backgrounds, rather than leaving a
            // stale "sharing" doc in Firestore no one is updating anymore.
            if newPhase == .background {
                locationSharing.stop()
            }
        }
    }

    /// Every local-only trip (`ownerUID == nil`) — whether created while
    /// signed out, or created while signed in but never actually confirmed
    /// uploaded (e.g. no network at the time) — gets a Firestore membership
    /// record here. `ownerUID` is only set once the upload actually
    /// succeeds, so a failed attempt stays retryable instead of silently
    /// looking "already synced."
    private func backfillOwnershipIfNeeded() {
        guard authService.isSignedIn, let uid = authService.firebaseUser?.uid else { return }
        for trip in trips where trip.ownerUID == nil {
            let tripID = trip.id
            let name = trip.name
            let location = trip.location
            let theme = trip.theme.rawValue
            let startDate = trip.startDate
            let endDate = trip.endDate
            let overallBudget = trip.overallBudget
            let currency = trip.currency
            let tripDescription = trip.tripDescription
            let latitude = trip.latitude
            let longitude = trip.longitude
            let visitedCountry = trip.visitedCountry
            let visitedProvince = trip.visitedProvince
            let visitedCity = trip.visitedCity
            let activityDTOs = trip.activities.map { ($0.id, $0.dto) }
            let accommodationDTOs = trip.accommodations.map { ($0.id, $0.dto) }
            let budgetCategoryDTOs = trip.budgetCategories.map { ($0.id, $0.dto) }
            let preparationTaskDTOs = trip.preparationTasks.map { ($0.id, $0.dto) }
            let transportSegmentDTOs = trip.transportSegments.map { ($0.id, $0.dto) }
            let dayNoteDTOs = trip.dayNotes.map { ($0.id, $0.dto) }
            let expenseDTOs = trip.expenses.map { ($0.id, $0.dto) }

            Task { @MainActor in
                do {
                    try await TripMembershipService.createTripRecord(
                        tripID: tripID, ownerUID: uid, name: name, location: location,
                        theme: theme, startDate: startDate, endDate: endDate,
                        overallBudget: overallBudget, currency: currency, tripDescription: tripDescription,
                        latitude: latitude, longitude: longitude,
                        visitedCountry: visitedCountry, visitedProvince: visitedProvince, visitedCity: visitedCity
                    )
                } catch {
                    return // stays ownerUID == nil; retried next foreground/sign-in
                }
                trip.ownerUID = uid
                for (id, dto) in activityDTOs {
                    try? await FirestoreCollectionSync.push(tripID: tripID, collection: "activities", docID: id, data: dto)
                }
                for (id, dto) in accommodationDTOs {
                    try? await FirestoreCollectionSync.push(tripID: tripID, collection: "accommodations", docID: id, data: dto)
                }
                for (id, dto) in budgetCategoryDTOs {
                    try? await FirestoreCollectionSync.push(tripID: tripID, collection: "budgetCategories", docID: id, data: dto)
                }
                for (id, dto) in preparationTaskDTOs {
                    try? await FirestoreCollectionSync.push(tripID: tripID, collection: "preparationTasks", docID: id, data: dto)
                }
                for (id, dto) in transportSegmentDTOs {
                    try? await FirestoreCollectionSync.push(tripID: tripID, collection: "transportSegments", docID: id, data: dto)
                }
                for (id, dto) in dayNoteDTOs {
                    try? await FirestoreCollectionSync.push(tripID: tripID, collection: "dayNotes", docID: id, data: dto)
                }
                for (id, dto) in expenseDTOs {
                    try? await FirestoreCollectionSync.push(tripID: tripID, collection: "expenses", docID: id, data: dto)
                }
            }
        }
    }
}

/// App-wide indicator that a trip's live location sharing is on, so it's
/// visible from any tab or trip subpage, not just the map screen where it
/// was started. Doubles as a one-tap way to stop broadcasting.
private struct LiveSharingBanner: View {
    let tripName: String
    let onStop: () -> Void

    var body: some View {
        Button(action: onStop) {
            HStack(spacing: 8) {
                Image(systemName: "location.fill")
                    .foregroundStyle(.green)
                Text("Sharing location · \(tripName)")
                    .font(AppFont.outfit(13, weight: .medium, relativeTo: .footnote))
                    .lineLimit(1)
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.thinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sharing location for \(tripName). Double tap to stop.")
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: Trip.self, inMemory: true)
}

struct BackgroundImageModifier: View {
    var body: some View {
        Image("light-bg")
            .scaledToFill()
            .ignoresSafeArea()
    }
}
