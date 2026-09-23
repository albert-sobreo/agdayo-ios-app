import SwiftUI
import SwiftData
import FirebaseAuth

struct RootTabView: View {
    @Query private var trips: [Trip]
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var authService

    @State private var deepLinkCode: String = ""
    @State private var isPresentingDeepLinkJoin = false

    var body: some View {
        TabView {
            Tab("Trips", systemImage: "suitcase.fill") {
                NavigationStack {
                    TripListView()
                        .background(BackgroundImageModifier())
                }
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
            JoinTripSheet(initialCode: deepLinkCode)
        }
        .task(id: authService.isSignedIn) {
            backfillOwnershipIfNeeded()
            if let uid = authService.firebaseUser?.uid {
                await TripDiscoveryService.refreshMemberTrips(uid: uid, localTrips: trips, modelContext: modelContext)
            }
        }
    }

    /// The moment a user signs in, every local trip they created while signed
    /// out gets a Firestore membership record, so nothing is permanently
    /// stuck local-only.
    private func backfillOwnershipIfNeeded() {
        guard authService.isSignedIn, let uid = authService.firebaseUser?.uid else { return }
        for trip in trips where trip.ownerUID == nil {
            trip.ownerUID = uid
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

            Task {
                try? await TripMembershipService.createTripRecord(
                    tripID: tripID, ownerUID: uid, name: name, location: location,
                    theme: theme, startDate: startDate, endDate: endDate,
                    overallBudget: overallBudget, currency: currency, tripDescription: tripDescription,
                    latitude: latitude, longitude: longitude
                )
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
