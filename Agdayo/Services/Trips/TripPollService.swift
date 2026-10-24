import FirebaseFirestore
import Foundation
import SwiftData

/// Everything that changes a poll after it's created. Each change is applied
/// locally first, then pushed as a targeted field update for shared trips, so
/// two members voting at the same moment never overwrite each other.
enum TripPollService {
    private static let collection = "polls"

    /// Casts, changes, or (when `option` is the one already chosen) withdraws `uid`'s vote.
    @MainActor
    static func vote(_ poll: TripPoll, option: Int, uid: String, in trip: Trip) {
        guard !poll.isClosed, poll.options.indices.contains(option) else { return }
        let field: Any
        if poll.votes[uid] == option {
            poll.votes.removeValue(forKey: uid)
            field = FieldValue.delete()
        } else {
            poll.votes[uid] = option
            field = option
        }
        push(fields: [FieldPath(["votes", uid]): field], for: poll, in: trip)
    }

    @MainActor
    static func close(_ poll: TripPoll, in trip: Trip) {
        guard !poll.isClosed else { return }
        poll.isClosed = true
        push(fields: ["isClosed": true], for: poll, in: trip)
    }

    /// Adds the proposed activity to the itinerary and closes the vote.
    @MainActor
    static func approve(_ poll: TripPoll, in trip: Trip, modelContext: ModelContext) {
        guard poll.kind == .activityProposal, !poll.isClosed else { return }
        let activity = ActivitySaver.insert(
            title: poll.question,
            location: poll.location,
            coordinate: poll.coordinate,
            date: poll.proposedDate ?? trip.startDate,
            iconName: poll.iconName,
            trip: trip,
            modelContext: modelContext
        )
        NotificationScheduler.scheduleReminder(for: activity)
        close(poll, in: trip)
    }

    @MainActor
    static func delete(_ poll: TripPoll, in trip: Trip, modelContext: ModelContext) {
        if trip.ownerUID != nil {
            let tripID = trip.id
            let pollID = poll.id
            Task {
                try? await FirestoreCollectionSync.pushDelete(tripID: tripID, collection: collection, docID: pollID)
            }
        }
        modelContext.delete(poll)
    }

    /// Pushes a brand-new poll to Firestore (shared trips only).
    @MainActor
    static func pushIfShared(_ poll: TripPoll, in trip: Trip) {
        guard trip.ownerUID != nil else { return }
        let tripID = trip.id
        let pollID = poll.id
        let dto = poll.dto
        Task {
            try? await FirestoreCollectionSync.push(tripID: tripID, collection: collection, docID: pollID, data: dto)
        }
    }

    @MainActor
    private static func push(fields: [AnyHashable: Any], for poll: TripPoll, in trip: Trip) {
        guard trip.ownerUID != nil else { return }
        let tripID = trip.id
        let pollID = poll.id
        nonisolated(unsafe) let fields = fields
        Task {
            try? await FirestoreCollectionSync.updateFields(tripID: tripID, collection: collection, docID: pollID, fields: fields)
        }
    }
}
