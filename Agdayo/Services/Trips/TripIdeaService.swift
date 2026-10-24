import FirebaseFirestore
import Foundation
import SwiftData

/// Everything that changes an idea after it's created. Like polls, each change
/// is applied locally first, then pushed as a targeted field update for shared
/// trips, so two members reacting at once never overwrite each other.
enum TripIdeaService {
    private static let collection = "ideas"

    @MainActor
    static func pushIfShared(_ idea: TripIdea, in trip: Trip) {
        guard trip.ownerUID != nil else { return }
        let tripID = trip.id
        let ideaID = idea.id
        let dto = idea.dto
        Task {
            try? await FirestoreCollectionSync.push(tripID: tripID, collection: collection, docID: ideaID, data: dto)
        }
    }

    /// Adds `uid`'s 👍, or takes it back if they'd already given one.
    @MainActor
    static func toggleLike(_ idea: TripIdea, uid: String, in trip: Trip) {
        let field: Any
        if idea.likedBy.contains(uid) {
            idea.likedBy.removeAll { $0 == uid }
            field = FieldValue.arrayRemove([uid])
        } else {
            idea.likedBy.append(uid)
            field = FieldValue.arrayUnion([uid])
        }
        push(fields: ["likedBy": field], for: idea, in: trip)
    }

    /// Saves edits to an idea's own details, leaving its likes and planned state alone.
    @MainActor
    static func update(_ idea: TripIdea, in trip: Trip) {
        push(
            fields: [
                "title": idea.title,
                "note": idea.note,
                "location": idea.location,
                "link": idea.link,
                "latitude": idea.latitude.map { $0 as Any } ?? FieldValue.delete(),
                "longitude": idea.longitude.map { $0 as Any } ?? FieldValue.delete()
            ],
            for: idea, in: trip
        )
    }

    /// Adds the idea to the itinerary as an activity (an hour after the latest
    /// one, like a new activity) and marks the idea planned. It stays on the list.
    @MainActor
    @discardableResult
    static func approve(_ idea: TripIdea, in trip: Trip, modelContext: ModelContext) -> Activity? {
        guard !idea.isPlanned else { return nil }
        let tripID = trip.id
        let existing = (try? modelContext.fetch(FetchDescriptor<Activity>(predicate: #Predicate { $0.trip?.id == tripID }))) ?? []
        let activity = ActivitySaver.insert(
            title: idea.title,
            description: idea.note,
            location: idea.location,
            coordinate: idea.coordinate,
            date: ActivitySaver.defaultDate(for: trip, after: existing.map(\.date).max()),
            iconName: "mappin.and.ellipse",
            trip: trip,
            modelContext: modelContext
        )
        NotificationScheduler.scheduleReminder(for: activity)
        idea.isPlanned = true
        push(fields: ["isPlanned": true], for: idea, in: trip)
        return activity
    }

    @MainActor
    static func delete(_ idea: TripIdea, in trip: Trip, modelContext: ModelContext) {
        if trip.ownerUID != nil {
            let tripID = trip.id
            let ideaID = idea.id
            Task {
                try? await FirestoreCollectionSync.pushDelete(tripID: tripID, collection: collection, docID: ideaID)
            }
        }
        modelContext.delete(idea)
    }

    @MainActor
    private static func push(fields: [AnyHashable: Any], for idea: TripIdea, in trip: Trip) {
        guard trip.ownerUID != nil else { return }
        let tripID = trip.id
        let ideaID = idea.id
        // Already includes the change just made locally, for the fallback below.
        let fullDTO = idea.dto
        nonisolated(unsafe) let fields = fields
        Task {
            do {
                try await FirestoreCollectionSync.updateFields(tripID: tripID, collection: collection, docID: ideaID, fields: fields)
            } catch let error as NSError
                where error.domain == FirestoreErrorDomain && error.code == FirestoreErrorCode.notFound.rawValue {
                // The idea never reached Firestore (e.g. added while offline) — create it instead.
                try? await FirestoreCollectionSync.push(tripID: tripID, collection: collection, docID: ideaID, data: fullDTO)
            } catch {
                // Anything else (e.g. no permission) isn't something a retry would fix.
            }
        }
    }
}
