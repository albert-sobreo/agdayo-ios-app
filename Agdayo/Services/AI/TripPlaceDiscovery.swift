import CoreLocation
import MapKit

@available(iOS 26.0, *)
enum TripPlaceDiscovery {

    struct PlaceCandidate {
        let name: String
        let category: String
        let coordinate: CLLocationCoordinate2D
    }

    private static let searchRadius: CLLocationDistance = 5_000

    private static let categories = [
        ("attractions", "Attraction"),
        ("restaurants", "Restaurant"),
        ("cafes", "Cafe"),
        ("museums", "Museum"),
        ("parks", "Park")
    ]

    static func search(
        near center: CLLocationCoordinate2D,
        destination: String
    ) async -> [PlaceCandidate] {

        let results = await withTaskGroup(
            of: [PlaceCandidate].self,
            returning: [[PlaceCandidate]].self
        ) { group in

            for (queryCategory, displayCategory) in categories {
                group.addTask {
                    await searchCategory(
                        destination: destination,
                        queryCategory: queryCategory,
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

                if unique.count >= 15 {
                    return unique
                }
            }
        }

        return unique
    }

    private static func searchCategory(
        destination: String,
        queryCategory: String,
        displayCategory: String,
        center: CLLocationCoordinate2D
    ) async -> [PlaceCandidate] {

        let request = MKLocalSearch.Request()

        request.naturalLanguageQuery = "\(destination) \(queryCategory)"

        request.region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: searchRadius,
            longitudinalMeters: searchRadius
        )

        guard let response = try? await MKLocalSearch(request: request).start()
        else {
            return []
        }

        return response.mapItems
            .prefix(3)
            .compactMap { item in

                guard let name = item.name else {
                    return nil
                }

                return PlaceCandidate(
                    name: name,
                    category: displayCategory,
                    coordinate: item.placemark.coordinate
                )
            }
    }
}
