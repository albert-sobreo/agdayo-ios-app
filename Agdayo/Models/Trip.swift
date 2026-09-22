import Foundation
import SwiftData

enum TripTheme: String, Codable, CaseIterable, Identifiable {
    case peach, blue, amber, emerald

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }
}

enum TripStatus: String {
    case upcoming = "Upcoming"
    case active = "Active"
    case completed = "Completed"
}

@Model
final class Trip {
    @Attribute(.unique) var id: UUID
    var name: String
    var location: String
    var theme: TripTheme
    var startDate: Date
    var endDate: Date
    var overallBudget: Double
    var currency: String
    var tripDescription: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Activity.trip)
    var activities: [Activity] = []

    @Relationship(deleteRule: .cascade, inverse: \Accommodation.trip)
    var accommodations: [Accommodation] = []

    @Relationship(deleteRule: .cascade, inverse: \BudgetCategory.trip)
    var budgetCategories: [BudgetCategory] = []

    @Relationship(deleteRule: .cascade, inverse: \PreparationTask.trip)
    var preparationTasks: [PreparationTask] = []

    @Relationship(deleteRule: .cascade, inverse: \TransportSegment.trip)
    var transportSegments: [TransportSegment] = []

    @Relationship(deleteRule: .cascade, inverse: \DayNote.trip)
    var dayNotes: [DayNote] = []

    init(
        id: UUID = UUID(),
        name: String,
        location: String,
        theme: TripTheme = .peach,
        startDate: Date,
        endDate: Date,
        overallBudget: Double = 0,
        currency: String = "PHP",
        tripDescription: String = ""
    ) {
        self.id = id
        self.name = name
        self.location = location
        self.theme = theme
        self.startDate = startDate
        self.endDate = endDate
        self.overallBudget = overallBudget
        self.currency = currency
        self.tripDescription = tripDescription
        self.createdAt = .now
        self.updatedAt = .now
    }

    /// Always computed from dates, never stored, so it can't drift from reality.
    var status: TripStatus {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        if today < calendar.startOfDay(for: startDate) { return .upcoming }
        if today > calendar.startOfDay(for: endDate) { return .completed }
        return .active
    }

    var budgetedTotal: Double {
        budgetCategories.reduce(0) { $0 + $1.amount }
    }

    var isOverBudget: Bool {
        overallBudget > 0 && budgetedTotal > overallBudget
    }

    var numberOfDays: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        return max(1, (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1)
    }
}
