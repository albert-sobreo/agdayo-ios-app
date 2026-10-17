import CoreLocation
import MapKit

private actor PlaceSearchCache {
    private var storage: [String: [Candidate]] = [:]

    func results(for key: String) -> [Candidate]? { storage[key] }
    func store(_ results: [Candidate], for key: String) { storage[key] = results }
}

/// MapKit side of Plan My Day: per-kind POI searches (sequential, cached),
/// plus resolving the trip center and hotel anchor. `DayPlanner` never
/// touches this — it only sees the `Candidate`s that come out.
enum PlaceSearchService {

    static let radius: CLLocationDistance = 3_000
    static let perKindLimit = 8

    private static let cache = PlaceSearchCache()

    // MARK: Candidates

    /// One search per kind, run sequentially — a single POI search returns a
    /// limited result set and MapKit throttles bursts, so firing every
    /// category at once drops results. Non-empty results are cached per ~1 km
    /// grid cell so Shuffle and re-plans don't re-hit MapKit.
    static func fetchCandidates(kinds: Set<PlaceKind>, near center: CLLocationCoordinate2D) async -> [Candidate] {
        var all: [Candidate] = []
        var seen = Set<String>()
        for kind in kinds.sorted(by: { $0.rawValue < $1.rawValue }) {
            for candidate in await results(for: kind, near: center)
            where seen.insert(DayPlanner.key(candidate.name)).inserted {
                all.append(candidate)
            }
        }
        return all
    }

    private static func results(for kind: PlaceKind, near center: CLLocationCoordinate2D) async -> [Candidate] {
        let key = "\(kind.rawValue)|\((center.latitude * 100).rounded())|\((center.longitude * 100).rounded())"
        if let cached = await cache.results(for: key) { return cached }

        let places = await TripPlaceDiscovery.searchCategory(
            filter: [kind.mapKitCategory],
            displayCategory: kind.rawValue,
            center: center,
            radius: radius,
            limit: perKindLimit
        )
        let candidates = places.map {
            Candidate(name: $0.name, kind: kind, coordinate: $0.coordinate, locality: $0.locality)
        }
        if !candidates.isEmpty {
            await cache.store(candidates, for: key)
        }
        return candidates
    }

    // MARK: Anchors

    /// The trip's own coordinate, or a one-off geocode of its destination
    /// text for trips saved before they stored one.
    @MainActor
    static func searchCenter(for trip: Trip) async -> CLLocationCoordinate2D? {
        if let coordinate = trip.coordinate { return coordinate }
        return await resolve(trip.location, near: nil)
    }

    /// Where the traveler is staying that night, if the trip has an
    /// accommodation covering `day`. `Accommodation` stores only an address
    /// string, so it's geocoded here at plan time.
    @MainActor
    static func hotelAnchor(for trip: Trip, day: Date, near center: CLLocationCoordinate2D) async -> CLLocationCoordinate2D? {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        guard let stay = trip.accommodations.first(where: {
            calendar.startOfDay(for: $0.startDate) <= dayStart && dayStart <= calendar.startOfDay(for: $0.endDate)
        }) else { return nil }
        let query = stay.location.isEmpty ? stay.name : stay.location
        return await resolve(query, near: center)
    }

    private static func resolve(_ query: String, near center: CLLocationCoordinate2D?) async -> CLLocationCoordinate2D? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        if let center {
            request.region = MKCoordinateRegion(center: center, latitudinalMeters: 20_000, longitudinalMeters: 20_000)
        }
        let response = try? await MKLocalSearch(request: request).start()
        return response?.mapItems.first?.placemark.coordinate
    }
}

extension PlaceKind {
    var mapKitCategory: MKPointOfInterestCategory {
        switch self {
        case .museum: return .museum
        case .theater: return .theater
        case .park: return .park
        case .beach: return .beach
        case .nationalPark: return .nationalPark
        case .store: return .store
        case .zoo: return .zoo
        case .aquarium: return .aquarium
        case .amusementPark: return .amusementPark
        case .foodMarket: return .foodMarket
        case .nightlife: return .nightlife
        case .restaurant: return .restaurant
        case .cafe: return .cafe
        case .bakery: return .bakery
        }
    }

    /// Always a name from `ActivityIconLibrary.allIcons`, so planned stops
    /// render like any hand-added activity.
    var activityIconName: String {
        switch self {
        case .restaurant, .foodMarket: return "fork.knife"
        case .cafe, .bakery: return "cup.and.saucer"
        case .nightlife: return "wineglass"
        case .theater: return "theatermasks"
        case .museum: return "camera"
        case .zoo, .aquarium, .amusementPark: return "ticket"
        case .park, .beach, .nationalPark: return "figure.walk.motion"
        case .store: return "mappin.and.ellipse"
        }
    }
}
