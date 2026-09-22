import Foundation
import SwiftData

enum TransportMode: String, Codable, CaseIterable, Identifiable {
    case flight, bus, train, car, ferry, rideshare, other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flight: return "Flight"
        case .bus: return "Bus"
        case .train: return "Train"
        case .car: return "Car"
        case .ferry: return "Ferry"
        case .rideshare: return "Taxi/Ride-share"
        case .other: return "Other"
        }
    }

    var iconName: String {
        switch self {
        case .flight: return "airplane"
        case .bus: return "bus"
        case .train: return "tram"
        case .car: return "car"
        case .ferry: return "ferry"
        case .rideshare: return "car.circle"
        case .other: return "arrow.triangle.turn.up.right.circle"
        }
    }
}

@Model
final class TransportSegment {
    @Attribute(.unique) var id: UUID
    var mode: TransportMode
    var departureLocation: String
    var departureDate: Date
    var departureTime: String
    var arrivalLocation: String
    var arrivalDate: Date?
    var arrivalTime: String?
    var bookingRef: String?
    var seatNumber: String?
    var cost: Double
    var currency: String
    var notes: String?
    var trip: Trip?

    init(
        id: UUID = UUID(),
        mode: TransportMode = .flight,
        departureLocation: String = "",
        departureDate: Date = .now,
        departureTime: String = "09:00",
        arrivalLocation: String = "",
        arrivalDate: Date? = nil,
        arrivalTime: String? = nil,
        bookingRef: String? = nil,
        seatNumber: String? = nil,
        cost: Double = 0,
        currency: String = "PHP",
        notes: String? = nil,
        trip: Trip? = nil
    ) {
        self.id = id
        self.mode = mode
        self.departureLocation = departureLocation
        self.departureDate = departureDate
        self.departureTime = departureTime
        self.arrivalLocation = arrivalLocation
        self.arrivalDate = arrivalDate
        self.arrivalTime = arrivalTime
        self.bookingRef = bookingRef
        self.seatNumber = seatNumber
        self.cost = cost
        self.currency = currency
        self.notes = notes
        self.trip = trip
    }
}
