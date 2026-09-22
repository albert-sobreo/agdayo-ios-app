import Foundation
import SwiftData
import CoreLocation

@Model
final class Activity {
    @Attribute(.unique) var id: UUID
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
    var trip: Trip?

    init(
        id: UUID = UUID(),
        title: String,
        activityDescription: String = "",
        location: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        date: Date = .now,
        cost: Double? = nil,
        costCurrency: String? = nil,
        costNote: String? = nil,
        iconName: String = "mappin.and.ellipse",
        trip: Trip? = nil
    ) {
        self.id = id
        self.title = title
        self.activityDescription = activityDescription
        self.location = location
        self.latitude = latitude
        self.longitude = longitude
        self.date = date
        self.cost = cost
        self.costCurrency = costCurrency
        self.costNote = costNote
        self.iconName = iconName
        self.trip = trip
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
