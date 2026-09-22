import Foundation
import SwiftData

/// Finds trips a user is a Firestore member of but doesn't have locally yet
/// (materializing them into SwiftData), and refreshes already-known shared
/// trips' top-level fields. Shared by the sign-in check in `RootTabView` and
/// the pull-to-refresh gesture in `TripListView`.
@MainActor
enum TripDiscoveryService {
    static func refreshMemberTrips(uid: String, localTrips: [Trip], modelContext: ModelContext) async {
        for trip in localTrips where trip.ownerUID != nil {
            if let fields = try? await TripMembershipService.fetchTripFields(tripID: trip.id) {
                trip.name = fields.name
                trip.location = fields.location
                trip.theme = TripTheme(rawValue: fields.theme) ?? trip.theme
                trip.startDate = fields.startDate
                trip.endDate = fields.endDate
                trip.overallBudget = fields.overallBudget
                trip.currency = fields.currency
                trip.tripDescription = fields.tripDescription
            }
        }

        let existingIDs = Set(localTrips.map(\.id))
        print("[TripDiscovery] uid=\(uid) existingLocalTripIDs=\(existingIDs)")
        let tripIDs: [UUID]
        do {
            tripIDs = try await TripMembershipService.fetchMemberTripIDs(uid: uid)
            print("[TripDiscovery] fetchMemberTripIDs returned: \(tripIDs)")
        } catch {
            print("[TripDiscovery] fetchMemberTripIDs FAILED: \(error)")
            return
        }
        for tripID in tripIDs where !existingIDs.contains(tripID) {
            print("[TripDiscovery] materializing tripID=\(tripID)")
            await materializeTrip(tripID: tripID, modelContext: modelContext)
        }
    }

    private static func materializeTrip(tripID: UUID, modelContext: ModelContext) async {
        let fields: TripFieldsDTO
        do {
            guard let fetched = try await TripMembershipService.fetchTripFields(tripID: tripID) else {
                print("[TripDiscovery] fetchTripFields returned nil (doc doesn't exist) for \(tripID)")
                return
            }
            fields = fetched
            print("[TripDiscovery] fetchTripFields succeeded for \(tripID): name=\(fields.name)")
        } catch {
            print("[TripDiscovery] fetchTripFields FAILED for \(tripID): \(error)")
            return
        }
        let trip = Trip(
            id: tripID,
            name: fields.name,
            location: fields.location,
            theme: TripTheme(rawValue: fields.theme) ?? .peach,
            startDate: fields.startDate,
            endDate: fields.endDate,
            overallBudget: fields.overallBudget,
            currency: fields.currency,
            tripDescription: fields.tripDescription
        )
        trip.ownerUID = fields.ownerUID
        modelContext.insert(trip)

        if let activities = try? await FirestoreCollectionSync.fetchAll(tripID: tripID, collection: "activities", as: ActivityDTO.self) {
            for (id, dto) in activities {
                guard let uuid = UUID(uuidString: id) else { continue }
                modelContext.insert(Activity(id: uuid, dto: dto, trip: trip))
            }
        }
        if let accommodations = try? await FirestoreCollectionSync.fetchAll(tripID: tripID, collection: "accommodations", as: AccommodationDTO.self) {
            for (id, dto) in accommodations {
                guard let uuid = UUID(uuidString: id) else { continue }
                modelContext.insert(Accommodation(id: uuid, dto: dto, trip: trip))
            }
        }
        if let categories = try? await FirestoreCollectionSync.fetchAll(tripID: tripID, collection: "budgetCategories", as: BudgetCategoryDTO.self) {
            for (id, dto) in categories {
                guard let uuid = UUID(uuidString: id) else { continue }
                modelContext.insert(BudgetCategory(id: uuid, dto: dto, trip: trip))
            }
        }
        if let tasks = try? await FirestoreCollectionSync.fetchAll(tripID: tripID, collection: "preparationTasks", as: PreparationTaskDTO.self) {
            for (id, dto) in tasks {
                guard let uuid = UUID(uuidString: id) else { continue }
                modelContext.insert(PreparationTask(id: uuid, dto: dto, trip: trip))
            }
        }
        if let segments = try? await FirestoreCollectionSync.fetchAll(tripID: tripID, collection: "transportSegments", as: TransportSegmentDTO.self) {
            for (id, dto) in segments {
                guard let uuid = UUID(uuidString: id) else { continue }
                modelContext.insert(TransportSegment(id: uuid, dto: dto, trip: trip))
            }
        }
        if let notes = try? await FirestoreCollectionSync.fetchAll(tripID: tripID, collection: "dayNotes", as: DayNoteDTO.self) {
            for (id, dto) in notes {
                guard let uuid = UUID(uuidString: id) else { continue }
                modelContext.insert(DayNote(id: uuid, dto: dto, trip: trip))
            }
        }
    }
}
