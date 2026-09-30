import FirebaseFirestore
import Observation

/// App-wide (injected once at `RootTabView`, not per-screen) so a live
/// sharing session survives navigating between a trip's subpages and other
/// tabs — the old per-`TripMapView` `@State` stopped sharing the instant you
/// left the map, which is the "while user is not viewing the trip details
/// map" gap being closed here. Still foreground-only: nothing gets delivered
/// once iOS actually suspends the app, since permission stays "when in use."
@MainActor
@Observable
final class LiveLocationSharingCoordinator {
    private(set) var sharingTrip: Trip?
    private(set) var isSharing = false

    private let tracker = LiveLocationTracker()
    private var sharingUID: String?

    func isSharing(tripID: Trip.ID) -> Bool {
        isSharing && sharingTrip?.id == tripID
    }

    func toggleSharing(trip: Trip, uid: String) {
        if isSharing(tripID: trip.id) {
            stop()
        } else {
            start(trip: trip, uid: uid)
        }
    }

    func start(trip: Trip, uid: String) {
        stop() // only ever share one trip's location at a time
        sharingTrip = trip
        sharingUID = uid
        isSharing = true
        tracker.requestPermission()
        let tripID = trip.id
        tracker.start { coordinate in
            Task {
                try? await FirestoreCollectionSync.push(
                    tripID: tripID, collection: "liveLocations", docID: uid,
                    data: LiveLocationDTO(uid: uid, latitude: coordinate.latitude, longitude: coordinate.longitude, updatedAt: .now)
                )
            }
        }
    }

    func stop() {
        guard isSharing, let trip = sharingTrip, let uid = sharingUID else { return }
        tracker.stop()
        let tripID = trip.id
        Task { try? await FirestoreCollectionSync.pushDelete(tripID: tripID, collection: "liveLocations", docID: uid) }
        isSharing = false
        sharingTrip = nil
        sharingUID = nil
    }
}
