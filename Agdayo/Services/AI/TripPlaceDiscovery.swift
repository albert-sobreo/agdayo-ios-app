import CoreLocation
import MapKit

/// Grounds AI suggestion generation in real places. Uses category-filtered
/// POI search (`MKLocalPointsOfInterestRequest` + `MKPointOfInterestFilter`)
/// rather than natural-language queries like "Taipei restaurants" — matching
/// against Apple Maps' own structured POI categories is far more reliable
/// than hoping a free-text search ranks the right kind of place first, and
/// it's the main lever available for improving suggestion quality without
/// a bigger language model.
@available(iOS 26.0, *)
enum TripPlaceDiscovery {

    struct PlaceCandidate {
        let name: String
        let category: String
        let coordinate: CLLocationCoordinate2D
        /// A short "neighborhood, city" hint when MapKit has one, so the
        /// model can anchor descriptions to a real part of town instead of
        /// guessing.
        let locality: String?
    }

    private static let searchRadius: CLLocationDistance = 5_000
    /// How many of the closest results to keep per category.
    private static let perCategoryLimit = 6
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

    private static func searchCategory(
        filter: [MKPointOfInterestCategory],
        displayCategory: String,
        center: CLLocationCoordinate2D
    ) async -> [PlaceCandidate] {

        let request = MKLocalPointsOfInterestRequest(
            center: center,
            radius: searchRadius
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
                    locality: locality.isEmpty ? nil : locality
                )

                return (candidate, distance)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(perCategoryLimit)
            .map(\.0)
    }
}
