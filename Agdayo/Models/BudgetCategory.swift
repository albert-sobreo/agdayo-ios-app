import Foundation
import SwiftData

@Model
final class BudgetCategory {
    @Attribute(.unique) var id: UUID
    var name: String
    var amount: Double
    var trip: Trip?

    init(id: UUID = UUID(), name: String, amount: Double = 0, trip: Trip? = nil) {
        self.id = id
        self.name = name
        self.amount = amount
        self.trip = trip
    }
}
