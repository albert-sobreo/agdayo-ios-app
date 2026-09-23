import Foundation

struct ActivityDTO: Codable {
    var title: String
    var activityDescription: String
    var location: String
    var latitude: Double?
    var longitude: Double?
    var date: Date
    var cost: Double?
    var costCurrency: String?
    var costNote: String?
    var exchangeRateToTripCurrency: Double?
    var iconName: String
    var paidByUID: String?
    var splitUIDs: [String]?
    var splitAmounts: [String: Double]?
}

extension Activity {
    var dto: ActivityDTO {
        ActivityDTO(
            title: title,
            activityDescription: activityDescription,
            location: location,
            latitude: latitude,
            longitude: longitude,
            date: date,
            cost: cost,
            costCurrency: costCurrency,
            costNote: costNote,
            exchangeRateToTripCurrency: exchangeRateToTripCurrency,
            iconName: iconName,
            paidByUID: paidByUID,
            splitUIDs: splitUIDs,
            splitAmounts: splitAmounts.isEmpty ? nil : splitAmounts
        )
    }

    convenience init(id: UUID, dto: ActivityDTO, trip: Trip) {
        self.init(
            id: id,
            title: dto.title,
            activityDescription: dto.activityDescription,
            location: dto.location,
            latitude: dto.latitude,
            longitude: dto.longitude,
            date: dto.date,
            cost: dto.cost,
            costCurrency: dto.costCurrency,
            costNote: dto.costNote,
            exchangeRateToTripCurrency: dto.exchangeRateToTripCurrency,
            iconName: dto.iconName,
            paidByUID: dto.paidByUID,
            splitUIDs: dto.splitUIDs ?? [],
            splitAmounts: dto.splitAmounts ?? [:],
            trip: trip
        )
    }

    func apply(_ dto: ActivityDTO) {
        title = dto.title
        activityDescription = dto.activityDescription
        location = dto.location
        latitude = dto.latitude
        longitude = dto.longitude
        date = dto.date
        cost = dto.cost
        costCurrency = dto.costCurrency
        costNote = dto.costNote
        exchangeRateToTripCurrency = dto.exchangeRateToTripCurrency
        iconName = dto.iconName
        paidByUID = dto.paidByUID
        splitUIDs = dto.splitUIDs ?? []
        splitAmounts = dto.splitAmounts ?? [:]
    }
}
