import CoreLocation
import Foundation
import MapKit

/// Pure rules behind the itinerary's travel rows: which stay a day starts
/// from, which way of getting around to show first, when to leave, and
/// whether two stops are too close together. Kept free of SwiftUI and
/// networking so it can be unit tested.
enum TravelPlanning {

    /// Straight-line distance under which walking is shown first.
    static let walkingThreshold: CLLocationDistance = 1_000

    /// The stay you wake up in on `day`: the one whose nights cover it,
    /// including its check-out morning. When two stays touch (check-out and
    /// check-in on the same day), the one you check out of wins, since that's
    /// where the day starts. Only stays pinned on the map count.
    static func stay(for day: Date, in stays: [Accommodation], calendar: Calendar = .current) -> Accommodation? {
        let dayStart = calendar.startOfDay(for: day)
        let covering = stays.filter { stay in
            stay.coordinate != nil
                && calendar.startOfDay(for: stay.startDate) <= dayStart
                && dayStart <= calendar.startOfDay(for: stay.endDate)
        }
        return covering.min { calendar.startOfDay(for: $0.startDate) < calendar.startOfDay(for: $1.startDate) }
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
    static func leaveBy(arrival: Date, travelTime: TimeInterval) -> Date {
        arrival.addingTimeInterval(-travelTime)
    }

    /// True when getting to the next stop takes longer than the time between
    /// the two stops' start times. Activities have no end time, so this only
    /// catches plans that can't work at all.
    static func isTight(previousStart: Date, nextStart: Date, travelTime: TimeInterval) -> Bool {
        travelTime > nextStart.timeIntervalSince(previousStart)
    }
}

// MARK: Arrival and departure

extension TravelPlanning {
    /// When you're ready to head on after arriving: bags and immigration
    /// after a flight, a short walk out for anything else.
    static func readyAfterArrival(mode: TransportMode, arrival: Date) -> Date {
        arrival.addingTimeInterval(mode == .flight ? 45 * 60 : 15 * 60)
    }

    /// When to be at the departure point, or nil for modes that pick you up
    /// where you are (car, taxi).
    static func beThereBy(mode: TransportMode, departure: Date) -> Date? {
        switch mode {
        case .flight: return departure.addingTimeInterval(-2 * 60 * 60)
        case .bus, .train, .ferry, .other: return departure.addingTimeInterval(-20 * 60)
        case .car, .rideshare: return nil
        }
    }

    /// Plain words for `beThereBy`, shown under the travel row.
    static func beThereNote(mode: TransportMode) -> String? {
        switch mode {
        case .flight: return "Allows 2 h at the airport"
        case .bus, .train, .ferry, .other: return "Allows 20 min before departure"
        case .car, .rideshare: return nil
        }
    }

    /// The pinned stay you head to after arriving: you're booked in that
    /// night and haven't checked out before you land.
    static func stay(afterArrivingAt arrival: Date, in stays: [Accommodation], calendar: Calendar = .current) -> Accommodation? {
        stays
            .filter { stay in
                stay.coordinate != nil
                    && calendar.startOfDay(for: stay.startDate) <= calendar.startOfDay(for: arrival)
                    && checkOut(of: stay, calendar: calendar) > arrival
            }
            .min { $0.startDate < $1.startDate }
    }

    /// The pinned stay you leave from for a departure: checked in before it
    /// leaves, and checking out that day or later.
    static func stay(beforeDepartingAt departure: Date, in stays: [Accommodation], calendar: Calendar = .current) -> Accommodation? {
        stays
            .filter { stay in
                stay.coordinate != nil
                    && checkIn(of: stay, calendar: calendar) < departure
                    && calendar.startOfDay(for: stay.endDate) >= calendar.startOfDay(for: departure)
            }
            .max { $0.startDate < $1.startDate }
    }

    static func checkIn(of stay: Accommodation, calendar: Calendar = .current) -> Date {
        combine(stay.startDate, time: stay.checkInTime, calendar: calendar)
    }

    static func checkOut(of stay: Accommodation, calendar: Calendar = .current) -> Date {
        combine(stay.endDate, time: stay.checkOutTime, calendar: calendar)
    }

    private static func combine(_ day: Date, time: String, calendar: Calendar) -> Date {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return day }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day) ?? day
    }
}

extension TransportSegment {
    var departureCoordinate: CLLocationCoordinate2D? {
        guard let departureLatitude, let departureLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: departureLatitude, longitude: departureLongitude)
    }

    var arrivalCoordinate: CLLocationCoordinate2D? {
        guard let arrivalLatitude, let arrivalLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: arrivalLatitude, longitude: arrivalLongitude)
    }
}

extension Accommodation {
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
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
