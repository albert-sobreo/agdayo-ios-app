import FirebaseFirestore
import Observation
import SwiftData

/// Keeps the signed-in person's trips live across the whole app (My Trips,
/// Home, widgets), whether a change came from another person or from Claude
/// through the connector, which writes straight to Firestore.
///
/// - Listens to `users/{uid}.memberOfTripIDs`, so a trip that Claude
///   creates, or that someone adds you to, appears right away. (Trips are
///   never removed from here: older memberships may predate this list.)
/// - Runs a `TripContentSyncCoordinator` (trip fields + all content) for
///   every shared trip that hasn't ended yet. Past trips are still live
///   while their page is open, via `TripDetailView`'s own coordinator;
///   leaving them out here keeps launch reads from growing with history.
///
/// Running alongside `TripDetailView`'s coordinator for the same trip is
/// fine: Firestore shares one server listener between identical queries,
/// and every `apply…` is an idempotent upsert.
@Observable
@MainActor
final class MyTripsLiveSync {
    private var uid: String?
    private var userListener: ListenerRegistration?
    private var tripCoordinators: [UUID: TripContentSyncCoordinator] = [:]
    /// Trip IDs being fetched for the first time, so a burst of snapshots
    /// doesn't materialize the same trip twice.
    private var materializing: Set<UUID> = []

    func start(uid: String, modelContext: ModelContext) {
        guard self.uid != uid else { return }
        stop()
        self.uid = uid
        userListener = Firestore.firestore().collection("users").document(uid).addSnapshotListener { [weak self] snapshot, _ in
            guard let snapshot else { return }
            let ids = (snapshot.data()?["memberOfTripIDs"] as? [String] ?? []).compactMap { UUID(uuidString: $0) }
            Task { @MainActor in
                await self?.applyMemberTripIDs(Set(ids), uid: uid, modelContext: modelContext)
            }
        }
    }

    func stop() {
        userListener?.remove()
        userListener = nil
        tripCoordinators.values.forEach { $0.stop() }
        tripCoordinators.removeAll()
        uid = nil
    }

    /// Call whenever the local trip list changes: starts listeners for
    /// shared trips that haven't ended and stops them for the rest.
    func update(trips: [Trip], modelContext: ModelContext) {
        guard let uid else { return }
        let today = Calendar.current.startOfDay(for: .now)
        let wanted = trips.filter { $0.ownerUID != nil && $0.endDate >= today }
        let wantedIDs = Set(wanted.map(\.id))

        for (id, coordinator) in tripCoordinators where !wantedIDs.contains(id) {
            coordinator.stop()
            tripCoordinators[id] = nil
        }
        for trip in wanted where tripCoordinators[trip.id] == nil {
            let coordinator = TripContentSyncCoordinator()
            tripCoordinators[trip.id] = coordinator
            let role = trip.ownerUID == uid ? "owner" : "member"
            let tripID = trip.id
            Task {
                // Same order as `TripDetailView`: the listeners fail for
                // good if they attach before the membership doc exists.
                try? await TripMembershipService.ensureMembership(tripID: tripID, uid: uid, role: role)
                guard tripCoordinators[tripID] === coordinator else { return }
                coordinator.start(for: trip, modelContext: modelContext)
            }
        }
    }

    private func applyMemberTripIDs(_ ids: Set<UUID>, uid: String, modelContext: ModelContext) async {
        guard self.uid == uid else { return }
        let localTrips = (try? modelContext.fetch(FetchDescriptor<Trip>())) ?? []
        let localIDs = Set(localTrips.map(\.id))

        for id in ids where !localIDs.contains(id) && !materializing.contains(id) {
            materializing.insert(id)
            await TripDiscoveryService.materializeTrip(tripID: id, modelContext: modelContext)
            materializing.remove(id)
        }
    }
}
