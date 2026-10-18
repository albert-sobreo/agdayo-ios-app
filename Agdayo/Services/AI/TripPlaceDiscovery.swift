import CoreLocation
import MapKit

/// Finds real places for Plan My Day. Uses category-filtered POI search
/// (`MKLocalPointsOfInterestRequest` + `MKPointOfInterestFilter`) rather than
/// only natural-language queries like "Taipei restaurants" — matching against
/// Apple Maps' own structured POI categories is more reliable than hoping a
/// free-text search ranks the right kind of place first.
// Pure MapKit, so it works on every device.
enum TripPlaceDiscovery {

    struct PlaceCandidate {
        let name: String
        let category: String
        let coordinate: CLLocationCoordinate2D
        /// A short "neighborhood, city" hint when MapKit has one, so the
        /// model can anchor descriptions to a real part of town instead of
        /// guessing.
        let locality: String?
        /// Apple Maps' stable id for the place, so a full place card can be
        /// loaded later. `nil` when MapKit didn't provide one.
        var mapItemIdentifier: String? = nil
        /// The city/town MapKit reports for the place.
        var city: String? = nil
    }

    static let defaultRadius: CLLocationDistance = 5_000
    /// How many of the closest results to keep per category.
    static let defaultPerCategoryLimit = 6
    private static let totalLimit = 24

    private static let categories: [(filter: [MKPointOfInterestCategory], displayCategory: String)] = [
        ([.landmark, .nationalMonument, .amusementPark, .aquarium, .zoo, .castle, .fortress], "Attraction"),
        ([.restaurant], "Restaurant"),
        ([.cafe, .bakery], "Cafe"),
        ([.museum], "Museum"),
        ([.park, .nationalPark], "Park")
    ]

    static func search(
        near center: CLLocationCoordinate2D,
        destination: String
    ) async -> [PlaceCandidate] {

        let results = await withTaskGroup(
            of: [PlaceCandidate].self,
            returning: [[PlaceCandidate]].self
        ) { group in

            for (filter, displayCategory) in categories {
                group.addTask {
                    await searchCategory(
                        filter: filter,
                        displayCategory: displayCategory,
                        center: center
                    )
                }
            }

            var collected: [[PlaceCandidate]] = []

            for await result in group {
                collected.append(result)
            }

            return collected
        }

        var unique: [PlaceCandidate] = []
        var seen = Set<String>()

        for categoryResults in results {
            for place in categoryResults {

                let key = place.name
                    .lowercased()
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard !key.isEmpty, !seen.contains(key) else {
                    continue
                }

                seen.insert(key)
                unique.append(place)

                if unique.count >= totalLimit {
                    return unique
                }
            }
        }

        return unique
    }

    /// One category-filtered POI search, closest results first. Internal so
    /// other planners (e.g. Plan My Day) can run their own per-category
    /// searches with a different radius/limit instead of the
    /// merged-and-capped `search(near:destination:)`.
    static func searchCategory(
        filter: [MKPointOfInterestCategory],
        displayCategory: String,
        center: CLLocationCoordinate2D,
        radius: CLLocationDistance = defaultRadius,
        limit: Int = defaultPerCategoryLimit
    ) async -> [PlaceCandidate] {

        let request = MKLocalPointsOfInterestRequest(
            center: center,
            radius: radius
        )

        request.pointOfInterestFilter = MKPointOfInterestFilter(including: filter)

        guard let response = try? await MKLocalSearch(request: request).start()
        else {
            return []
        }

        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)

        return response.mapItems
            .compactMap { item -> (PlaceCandidate, CLLocationDistance)? in

                guard let name = item.name else {
                    return nil
                }

                let coordinate = item.placemark.coordinate
                let distance = centerLocation.distance(
                    from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                )

                let locality = [item.placemark.subLocality, item.placemark.locality]
                    .compactMap { $0 }
                    .joined(separator: ", ")

                let candidate = PlaceCandidate(
                    name: name,
                    category: displayCategory,
                    coordinate: coordinate,
                    locality: locality.isEmpty ? nil : locality,
                    mapItemIdentifier: item.identifier?.rawValue,
                    city: item.placemark.locality
                )

                return (candidate, distance)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map(\.0)
    }
}
