import Foundation

struct TransportSegmentDTO: Codable {
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
}

extension TransportSegment {
    var dto: TransportSegmentDTO {
        TransportSegmentDTO(
            mode: mode,
            departureLocation: departureLocation,
            departureDate: departureDate,
            departureTime: departureTime,
            arrivalLocation: arrivalLocation,
            arrivalDate: arrivalDate,
            arrivalTime: arrivalTime,
            bookingRef: bookingRef,
            seatNumber: seatNumber,
            cost: cost,
            currency: currency,
            notes: notes
        )
    }

    convenience init(id: UUID, dto: TransportSegmentDTO, trip: Trip) {
        self.init(
            id: id,
            mode: dto.mode,
            departureLocation: dto.departureLocation,
            departureDate: dto.departureDate,
            departureTime: dto.departureTime,
            arrivalLocation: dto.arrivalLocation,
            arrivalDate: dto.arrivalDate,
            arrivalTime: dto.arrivalTime,
            bookingRef: dto.bookingRef,
            seatNumber: dto.seatNumber,
            cost: dto.cost,
            currency: dto.currency,
            notes: dto.notes,
            trip: trip
        )
    }

    func apply(_ dto: TransportSegmentDTO) {
        mode = dto.mode
        departureLocation = dto.departureLocation
        departureDate = dto.departureDate
        departureTime = dto.departureTime
        arrivalLocation = dto.arrivalLocation
        arrivalDate = dto.arrivalDate
        arrivalTime = dto.arrivalTime
        bookingRef = dto.bookingRef
        seatNumber = dto.seatNumber
        cost = dto.cost
        currency = dto.currency
        notes = dto.notes
    }
}
