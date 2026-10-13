import CoreLocation
import MapKit

@available(iOS 26.0, *)
enum ItineraryDistanceRanking {

    static func rank(
        _ groups: [SuggestionGroup],
        around tripCenter: CLLocationCoordinate2D?
    ) async -> [SuggestionGroup] {

        guard let tripCenter else {
            return groups
        }

        var anchor = tripCenter
        var rankedGroups: [SuggestionGroup] = []

        for group in groups {

            let resolved = await withTaskGroup(
                of: (SuggestionOption, CLLocationCoordinate2D?).self
            ) { taskGroup -> [(SuggestionOption, CLLocationCoordinate2D?)] in

                for option in group.options {
                    taskGroup.addTask {
                        (
                            option,
                            await resolveCoordinate(
                                for: option.location,
                                near: tripCenter
                            )
                        )
                    }
                }

                var results: [(SuggestionOption, CLLocationCoordinate2D?)] = []

                for await result in taskGroup {
                    results.append(result)
                }

                return results
            }

            let sorted = resolved.sorted {
                distance(
                    from: anchor,
                    to: $0.1
                ) < distance(
                    from: anchor,
                    to: $1.1
                )
            }

            var rankedGroup = group
            rankedGroup.options = sorted.map(\.0)
            rankedGroups.append(rankedGroup)

            if let closest = sorted.first?.1 {
                anchor = closest
            }
        }

        return rankedGroups
    }

    static func resolveCoordinate(
        for placeName: String,
        near center: CLLocationCoordinate2D
    ) async -> CLLocationCoordinate2D? {

        let request = MKLocalSearch.Request()

        request.naturalLanguageQuery = placeName

        request.region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: 20_000,
            longitudinalMeters: 20_000
        )

        let response = try? await MKLocalSearch(request: request).start()

        return response?.mapItems.first?.placemark.coordinate
    }

    private static func distance(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D?
    ) -> CLLocationDistance {

        guard let to else {
            return .greatestFiniteMagnitude
        }

        return CLLocation(
            latitude: from.latitude,
            longitude: from.longitude
        )
        .distance(
            from: CLLocation(
                latitude: to.latitude,
                longitude: to.longitude
            )
        )
    }
}
