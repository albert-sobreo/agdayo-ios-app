import CoreLocation
import Foundation
import MapKit

/// Pure rules behind the itinerary's travel rows between activities: which
/// way of getting around to show first, when to leave, and whether two
/// stops are too close together. Kept free of SwiftUI and
/// networking so it can be unit tested.
enum TravelPlanning {

    /// Straight-line distance under which walking is shown first.
    static let walkingThreshold: CLLocationDistance = 1_000

    /// What a row of a day's timeline is, as far as travel legs go.
    enum TimelineRowKind: Equatable {
        case activity
        /// A check-in or check-out row. Shown for context only.
        case stay
        /// A transport departure or arrival.
        case transport
    }

    /// Where the travel row into the activity at `index` starts: the closest
    /// earlier activity that day, looking past check-in and check-out rows.
    /// Stays never start or end a leg, and a transport row in between means
    /// you've moved on, so there's no leg. nil when `index` isn't an activity
    /// or nothing qualifies.
    static func legOriginIndex(before index: Int, in kinds: [TimelineRowKind]) -> Int? {
        guard kinds.indices.contains(index), kinds[index] == .activity else { return nil }
        for i in stride(from: index - 1, through: 0, by: -1) {
            switch kinds[i] {
            case .activity: return i
            case .stay: continue
            case .transport: return nil
            }
        }
        return nil
    }

    /// The mode a travel row opens on, before any directions are fetched:
    /// walking for short hops, otherwise transit. The row falls back to
    /// driving itself when transit has no route there (see
    /// `fallbackMode(after:)`).
    static func initialMode(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> MKDirectionsTransportType {
        let distance = CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
        return distance < walkingThreshold ? .walking : .transit
    }

    /// What to try next when the automatically chosen mode has no route,
    /// for example transit in a city without transit data. `nil` means stop.
    static func fallbackMode(after mode: MKDirectionsTransportType) -> MKDirectionsTransportType? {
        mode == .transit ? .automobile : nil
    }

    /// When to set off to reach `arrival` after `travelTime`.
    static func leaveBy(arrival: Date, travelTime: TimeInterval, spare: TimeInterval = 0) -> Date {
        arrival.addingTimeInterval(-travelTime - spare)
    }

    /// Spare time added to every leave-by shown or notified, so "leave by"
    /// doesn't mean "arrive exactly on the minute".
    static let leaveBySpare: TimeInterval = 5 * 60

    /// True when getting to the next stop takes longer than the time between
    /// the two stops' start times. Activities have no end time, so this only
    /// catches plans that can't work at all.
    static func isTight(previousStart: Date, nextStart: Date, travelTime: TimeInterval) -> Bool {
        travelTime > nextStart.timeIntervalSince(previousStart)
    }
}

extension MKDirectionsTransportType {
    /// The Apple Maps launch option matching this mode, for "Directions".
    /// Cycling has no launch option of its own, so it opens as driving.
    var mapsLaunchMode: String {
        switch self {
        case .walking: return MKLaunchOptionsDirectionsModeWalking
        case .transit: return MKLaunchOptionsDirectionsModeTransit
        default: return MKLaunchOptionsDirectionsModeDriving
        }
    }

    /// How the mode reads after a duration: "22 min by car", "8 min walk".
    var travelPhrase: String {
        switch self {
        case .walking: return "walk"
        case .transit: return "by transit"
        case .cycling: return "by bike"
        default: return "by car"
        }
    }

    /// Google Maps' `travelmode` for this mode.
    var googleTravelMode: String {
        switch self {
        case .walking: return "walking"
        case .transit: return "transit"
        case .cycling: return "bicycling"
        default: return "driving"
        }
    }
}

extension TravelPlanning {
    /// Directions in Google Maps. This universal link opens the Google Maps
    /// app when it's installed and the website otherwise, which is where to
    /// see transit lines and steps for cities Apple Maps doesn't cover.
    static func googleMapsURL(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, mode: MKDirectionsTransportType) -> URL? {
        var components = URLComponents(string: "https://www.google.com/maps/dir/")
        components?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "origin", value: "\(origin.latitude),\(origin.longitude)"),
            URLQueryItem(name: "destination", value: "\(destination.latitude),\(destination.longitude)"),
            URLQueryItem(name: "travelmode", value: mode.googleTravelMode),
        ]
        return components?.url
    }
}
