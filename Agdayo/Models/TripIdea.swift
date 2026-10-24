import Foundation
import SwiftData
import CoreLocation

/// Something the group would like to do on the trip, not yet scheduled. The
/// trip owner approves it, which adds an `Activity` and marks the idea planned.
@Model
final class TripIdea {
    @Attribute(.unique) var id: UUID
    var title: String
    var note: String
    var location: String
    var latitude: Double?
    var longitude: Double?
    var link: String
    var addedByUID: String
    var createdAt: Date
    /// Uids of members who 👍'd it — one each, so it's a set kept as an array.
    var likedBy: [String] = []
    /// Set when the owner approves it. The idea stays on the list, marked Planned.
    var isPlanned: Bool
    var trip: Trip?

    init(
        id: UUID = UUID(),
        title: String,
        note: String = "",
        location: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        link: String = "",
        addedByUID: String,
        createdAt: Date = .now,
        likedBy: [String] = [],
        isPlanned: Bool = false,
        trip: Trip? = nil
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.location = location
        self.latitude = latitude
        self.longitude = longitude
        self.link = link
        self.addedByUID = addedByUID
        self.createdAt = createdAt
        self.likedBy = likedBy
        self.isPlanned = isPlanned
        self.trip = trip
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// The link as a URL, if it looks like one (adds https:// when it's missing).
    var linkURL: URL? {
        let trimmed = link.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: withScheme), url.host != nil else { return nil }
        return url
    }

    /// Likes from `eligible` voters only (the trip's current members), so
    /// someone who left doesn't count. `nil` counts every like.
    func likeCount(among eligible: Set<String>? = nil) -> Int {
        guard let eligible else { return likedBy.count }
        return likedBy.filter { eligible.contains($0) }.count
    }
}
