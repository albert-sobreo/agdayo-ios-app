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
    var numberOfRooms: Int
    var totalCost: Double
    var checkInTime: String
    var checkOutTime: String
    var startDate: Date
    var endDate: Date
    var trip: Trip?

    init(
        id: UUID = UUID(),
        name: String,
        type: AccommodationType = .hotel,
        location: String = "",
        numberOfRooms: Int = 1,
        totalCost: Double = 0,
        checkInTime: String = "15:00",
        checkOutTime: String = "11:00",
        startDate: Date = .now,
        endDate: Date = .now,
        trip: Trip? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.location = location
        self.numberOfRooms = numberOfRooms
        self.totalCost = totalCost
        self.checkInTime = checkInTime
        self.checkOutTime = checkOutTime
        self.startDate = startDate
        self.endDate = endDate
        self.trip = trip
    }
}
