import Foundation
import SwiftData

/// A recorded real-world payment between two members, settling down (part
/// of) their computed balance — separate from `Activity`/`Accommodation`/
/// `TransportSegment` costs, which represent what was spent, not what's
/// since been paid back.
@Model
final class Settlement {
    @Attribute(.unique) var id: UUID
    var fromUID: String
    var toUID: String
    var amount: Double
    var date: Date
    var trip: Trip?

    init(
        id: UUID = UUID(),
        fromUID: String,
        toUID: String,
        amount: Double,
        date: Date = .now,
        trip: Trip? = nil
    ) {
        self.id = id
        self.fromUID = fromUID
        self.toUID = toUID
        self.amount = amount
        self.date = date
        self.trip = trip
    }
}
