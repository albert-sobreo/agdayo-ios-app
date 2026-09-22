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
    var iconName: String
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
            iconName: iconName
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
            iconName: dto.iconName,
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
        iconName = dto.iconName
    }
}
