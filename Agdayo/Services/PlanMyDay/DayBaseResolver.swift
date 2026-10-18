import CoreLocation
import Foundation
import MapKit

/// Where a day is based. Trips can span several cities, or include far day
/// trips, so Plan My Day searches around this instead of the trip's single
/// destination.
struct PlanBase: Equatable {
    var name: String
    var latitude: Double
    var longitude: Double
    /// Why this base was chosen, shown under the "Planning around" row.
    var reason: String
    /// A country, state, province or region rather than a town or city —
    /// too large for a radius around its center to mean anything.
    var isBroad = false
    /// How far from its center a broad area reaches, in meters, so results
    /// from elsewhere can be told apart ("Quezon City" is not in Bicol).
    var broadRadius: Double = 0

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(name: String, coordinate: CLLocationCoordinate2D, reason: String, isBroad: Bool = false, broadRadius: Double = 0) {
        self.name = name
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.reason = reason
        self.isBroad = isBroad
        self.broadRadius = broadRadius
    }

    /// "Makati, Philippines" -> "Makati": the part most likely to be a
    /// guide page title.
    var searchName: String {
        name.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? name
    }
}

/// Works out where the traveler is on a given day, most specific signal first:
/// activities already planned that day, the hotel they're staying at, the
/// latest transport arrival, then the trip's own destination.
@MainActor
enum DayBaseResolver {

    static func resolve(trip: Trip, day: Date) async -> PlanBase? {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)

        // 1. Activities already on that day (centroid of the ones with coordinates).
        let located = trip.activities.filter {
            calendar.startOfDay(for: $0.date) == dayStart && $0.coordinate != nil
        }
        if !located.isEmpty {
            let coordinates = located.compactMap(\.coordinate)
            let center = CLLocationCoordinate2D(
                latitude: coordinates.map(\.latitude).reduce(0, +) / Double(coordinates.count),
                longitude: coordinates.map(\.longitude).reduce(0, +) / Double(coordinates.count)
            )
            let name = await place(named: located[0].location, near: center)?.name
                ?? trip.location
            return PlanBase(name: name, coordinate: center, reason: "Where your planned activities are")
        }

        // 2. The accommodation covering that night.
        if let stay = trip.accommodations.first(where: {
            calendar.startOfDay(for: $0.startDate) <= dayStart && dayStart <= calendar.startOfDay(for: $0.endDate)
        }) {
            let query = stay.location.isEmpty ? stay.name : stay.location
            if let found = await place(named: query, near: trip.coordinate) {
                return PlanBase(name: found.name, coordinate: found.coordinate, reason: "Around your stay, \(stay.name)")
            }
        }

        // 3. The most recent transport arrival on or before that day.
        let arrival = trip.transportSegments
            .compactMap { segment -> (TransportSegment, Date)? in
                guard let date = segment.arrivalDate ?? Optional(segment.departureDate) else { return nil }
                return calendar.startOfDay(for: date) <= dayStart ? (segment, date) : nil
            }
            .max { $0.1 < $1.1 }
        if let (segment, _) = arrival, !segment.arrivalLocation.isEmpty,
           let found = await place(named: segment.arrivalLocation, near: trip.coordinate) {
            return PlanBase(name: found.name, coordinate: found.coordinate, reason: "Where you arrive on your \(segment.mode.displayName.lowercased())")
        }

        // 4. The trip's destination.
        return await tripDestination(for: trip)
    }

    /// Looks a text address/name up on the map. `name` is the town or city
    /// when MapKit knows it, else the query text.
    static func place(named query: String, near center: CLLocationCoordinate2D?) async -> (name: String, coordinate: CLLocationCoordinate2D, isBroad: Bool, broadRadius: Double)? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        if let center {
            request.region = MKCoordinateRegion(center: center, latitudinalMeters: 200_000, longitudinalMeters: 200_000)
        }
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        let placemark = item.placemark
        let name = placemark.locality ?? placemark.subAdministrativeArea ?? item.name ?? trimmed
        // No town or city in the result means the query named something
        // bigger: a province, state or country.
        // A result with no administrative area is a whole country; one with a
        // province or state but no city is a region.
        let radius: Double = placemark.locality != nil ? 0 : (placemark.administrativeArea == nil ? 1_200_000 : 250_000)
        return (name, placemark.coordinate, placemark.locality == nil, radius)
    }

    /// The trip's own destination as a base ("Makati").
    static func tripDestination(for trip: Trip) async -> PlanBase? {
        // Always look it up: even with a stored coordinate, the lookup is how
        // we learn whether the destination is a city or something bigger.
        let found = await place(named: trip.location, near: nil)
        if let coordinate = trip.coordinate ?? found?.coordinate {
            return PlanBase(
                name: trip.coordinate != nil ? trip.location : (found?.name ?? trip.location),
                coordinate: coordinate,
                reason: "Your trip destination",
                isBroad: found?.isBroad ?? false,
                broadRadius: found?.broadRadius ?? 0
            )
        }
        return nil
    }
}
