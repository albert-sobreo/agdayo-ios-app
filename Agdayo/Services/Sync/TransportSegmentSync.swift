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
    var exchangeRateToTripCurrency: Double?
    var notes: String?
    var budgetCategoryID: UUID?
    var budgetMemberUID: String?
    var paidByUID: String?
    var splitUIDs: [String]?
    var splitAmounts: [String: Double]?
    var departureLatitude: Double?
    var departureLongitude: Double?
    var arrivalLatitude: Double?
    var arrivalLongitude: Double?
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
            exchangeRateToTripCurrency: exchangeRateToTripCurrency,
            notes: notes,
            budgetCategoryID: budgetCategoryID,
            budgetMemberUID: budgetMemberUID,
            paidByUID: paidByUID,
            splitUIDs: splitUIDs,
            splitAmounts: splitAmounts.isEmpty ? nil : splitAmounts,
            departureLatitude: departureLatitude,
            departureLongitude: departureLongitude,
            arrivalLatitude: arrivalLatitude,
            arrivalLongitude: arrivalLongitude
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
            exchangeRateToTripCurrency: dto.exchangeRateToTripCurrency,
            notes: dto.notes,
            budgetCategoryID: dto.budgetCategoryID,
            budgetMemberUID: dto.budgetMemberUID,
            paidByUID: dto.paidByUID,
            splitUIDs: dto.splitUIDs ?? [],
            splitAmounts: dto.splitAmounts ?? [:],
            departureLatitude: dto.departureLatitude,
            departureLongitude: dto.departureLongitude,
            arrivalLatitude: dto.arrivalLatitude,
            arrivalLongitude: dto.arrivalLongitude,
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
        exchangeRateToTripCurrency = dto.exchangeRateToTripCurrency
        notes = dto.notes
        budgetCategoryID = dto.budgetCategoryID
        budgetMemberUID = dto.budgetMemberUID
        paidByUID = dto.paidByUID
        splitUIDs = dto.splitUIDs ?? []
        splitAmounts = dto.splitAmounts ?? [:]
        departureLatitude = dto.departureLatitude
        departureLongitude = dto.departureLongitude
        arrivalLatitude = dto.arrivalLatitude
        arrivalLongitude = dto.arrivalLongitude
    }
}
