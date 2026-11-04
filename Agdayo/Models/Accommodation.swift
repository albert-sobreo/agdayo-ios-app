import Foundation
import SwiftData

enum AccommodationType: String, Codable, CaseIterable, Identifiable {
    case hotel, airbnb, transient, other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hotel: return "Hotel"
        case .airbnb: return "AirBnb"
        case .transient: return "Transient"
        case .other: return "Other"
        }
    }
}

@Model
final class Accommodation {
    @Attribute(.unique) var id: UUID
    var name: String
    var type: AccommodationType
    var location: String
    /// Where the stay is on the map, set from the location search (or a
    /// one-time lookup for stays saved before this existed). Used to show
    /// travel from the stay to each day's first stop.
    var latitude: Double?
    var longitude: Double?
    var numberOfRooms: Int
    var totalCost: Double
    var checkInTime: String
    var checkOutTime: String
    var startDate: Date
    var endDate: Date
    /// Which planned budget category this expense counts against, if any —
    /// see `Activity.budgetCategoryID`.
    var budgetCategoryID: UUID?
    /// See `Activity.budgetMemberUID`.
    var budgetMemberUID: String?
    var paidByUID: String?
    var splitUIDs: [String] = []
    var splitAmounts: [String: Double] = [:]
    var trip: Trip?

    init(
        id: UUID = UUID(),
        name: String,
        type: AccommodationType = .hotel,
        location: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        numberOfRooms: Int = 1,
        totalCost: Double = 0,
        checkInTime: String = "15:00",
        checkOutTime: String = "11:00",
        startDate: Date = .now,
        endDate: Date = .now,
        budgetCategoryID: UUID? = nil,
        budgetMemberUID: String? = nil,
        paidByUID: String? = nil,
        splitUIDs: [String] = [],
        splitAmounts: [String: Double] = [:],
        trip: Trip? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.location = location
        self.latitude = latitude
        self.longitude = longitude
        self.numberOfRooms = numberOfRooms
        self.totalCost = totalCost
        self.checkInTime = checkInTime
        self.checkOutTime = checkOutTime
        self.startDate = startDate
        self.endDate = endDate
        self.budgetCategoryID = budgetCategoryID
        self.budgetMemberUID = budgetMemberUID
        self.paidByUID = paidByUID
        self.splitUIDs = splitUIDs
        self.splitAmounts = splitAmounts
        self.trip = trip
    }
}
