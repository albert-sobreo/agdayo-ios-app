import SwiftUI
import SwiftData
import FirebaseAuth

struct RootTabView: View {
    @Query private var trips: [Trip]
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var authService
    @Environment(\.scenePhase) private var scenePhase

    @State private var deepLinkCode: String = ""
    @State private var isPresentingDeepLinkJoin = false
    @State private var pendingJoinedTrip: Trip?

    var body: some View {
        TabView {
            Tab("Trips", systemImage: "suitcase.fill") {
                TripListView(pendingJoinedTrip: $pendingJoinedTrip)
            }
            Tab("Map", systemImage: "map.fill") {
                NavigationStack {
                    GlobalMapView()
                        .background(BackgroundImageModifier())
                }
            }
            Tab("Profile", systemImage: "person.crop.circle") {
                NavigationStack {
                    ProfileView()
                        .background(BackgroundImageModifier())
                }
            }
        }
        .tint(.appPrimary)
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
            JoinTripSheet(initialCode: deepLinkCode, onJoined: { trip in pendingJoinedTrip = trip })
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
            let activityDTOs = trip.activities.map { ($0.id, $0.dto) }
            let accommodationDTOs = trip.accommodations.map { ($0.id, $0.dto) }
            let budgetCategoryDTOs = trip.budgetCategories.map { ($0.id, $0.dto) }
            let preparationTaskDTOs = trip.preparationTasks.map { ($0.id, $0.dto) }
            let transportSegmentDTOs = trip.transportSegments.map { ($0.id, $0.dto) }
            let dayNoteDTOs = trip.dayNotes.map { ($0.id, $0.dto) }

            Task { @MainActor in
                do {
                    try await TripMembershipService.createTripRecord(
                        tripID: tripID, ownerUID: uid, name: name, location: location,
                        theme: theme, startDate: startDate, endDate: endDate,
                        overallBudget: overallBudget, currency: currency, tripDescription: tripDescription,
                        latitude: latitude, longitude: longitude
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
            }
        }
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
