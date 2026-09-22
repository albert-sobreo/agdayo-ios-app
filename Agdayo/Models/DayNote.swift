import Foundation
import SwiftData

@Model
final class DayNote {
    @Attribute(.unique) var id: UUID
    var day: Date
    var title: String
    var content: String
    var trip: Trip?

    init(id: UUID = UUID(), day: Date, title: String, content: String = "", trip: Trip? = nil) {
        self.id = id
        self.day = day
        self.title = title
        self.content = content
        self.trip = trip
    }
}
