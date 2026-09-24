import CoreLocation
import Foundation
import SwiftData

enum TripTheme: String, Codable, CaseIterable, Identifiable {
    case peach, blue, amber, emerald, violet, teal, rose, slate

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
    var latitude: Double?
    var longitude: Double?

    /// Reverse-geocoded from `coordinate`, self-healing the same way
    /// `latitude`/`longitude` are (see `GlobalMapView.geocodeMissingTrips()`
    /// and `VisitedPlacesMapView`'s equivalent backfill) — used to group
    /// completed trips by place for the visited-places map.
    var visitedCountry: String?
    var visitedProvince: String?
    var visitedCity: String?

    /// Firebase UID of the signed-in user who created this trip, if any.
    /// `nil` for trips created while signed out — those stay local-only until
    /// backfilled on a later sign-in. `Trip.id` doubles as the Firestore
    /// document ID once a membership record exists.
    var ownerUID: String?

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

    @Relationship(deleteRule: .cascade, inverse: \Settlement.trip)
    var settlements: [Settlement] = []

    init(
        id: UUID = UUID(),
        name: String,
        location: String,
        theme: TripTheme = .peach,
        startDate: Date,
        endDate: Date,
        overallBudget: Double = 0,
        currency: String = "PHP",
        tripDescription: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil
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
        self.latitude = latitude
        self.longitude = longitude
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Always computed from dates, never stored, so it can't drift from reality.
    var status: TripStatus {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        if today < calendar.startOfDay(for: startDate) { return .upcoming }
        if today > calendar.startOfDay(for: endDate) { return .completed }
        return .active
    }

    /// Activities' own `cost` fields, on top of the planned category
    /// amounts — converted into the trip's currency via each activity's
    /// snapshotted exchange rate. An activity costed in a different
    /// currency with no rate ever captured (e.g. entered fully offline) is
    /// excluded rather than mixed in wrong.
    var activityCostsTotal: Double {
        activities.reduce(0) { $0 + ($1.costAndRate(inTripCurrency: currency)?.cost ?? 0) }
    }

    /// Accommodations have no currency field of their own — `totalCost` is
    /// always assumed to be in the trip's currency.
    var accommodationCostsTotal: Double {
        accommodations.reduce(0) { $0 + $1.totalCost }
    }

    /// Same conversion as `activityCostsTotal`.
    var transportCostsTotal: Double {
        transportSegments.reduce(0) { $0 + ($1.costAndRate(inTripCurrency: currency)?.cost ?? 0) }
    }

    var budgetedTotal: Double {
        budgetCategories.reduce(0) { $0 + $1.amount }
            + activityCostsTotal
            + accommodationCostsTotal
            + transportCostsTotal
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

    /// How many of the core planning sections have at least one entry.
    /// Replaces the web app's inconsistent 5-of-7 progress math with a
    /// clean, always-in-sync computed value (companions/roles dropped).
    var planningProgress: (completed: Int, total: Int) {
        let sections = [
            !activities.isEmpty,
            !budgetCategories.isEmpty,
            !accommodations.isEmpty,
            !preparationTasks.isEmpty,
            !transportSegments.isEmpty,
        ]
        return (sections.filter { $0 }.count, sections.count)
    }
}
