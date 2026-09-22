import Foundation
import SwiftData

enum PreparationTaskSuggestion {
    static let defaults = ["Documents", "Packing", "Essentials"]
}

@Model
final class PreparationTask {
    @Attribute(.unique) var id: UUID
    var name: String
    var category: String
    var notes: String
    var completed: Bool
    var trip: Trip?

    init(
        id: UUID = UUID(),
        name: String,
        category: String = "Essentials",
        notes: String = "",
        completed: Bool = false,
        trip: Trip? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.notes = notes
        self.completed = completed
        self.trip = trip
    }
}
