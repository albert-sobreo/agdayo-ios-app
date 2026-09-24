import CoreLocation
import MapKit

@available(iOS 26.0, *)
enum ItineraryDistanceRanking {

    static func rank(
        _ days: [GeneratedDay],
        around tripCenter: CLLocationCoordinate2D?
    ) async -> [GeneratedDay] {

        guard let tripCenter else {
            return days
        }

        var anchor = tripCenter
        var rankedDays: [GeneratedDay] = []

        for day in days {

            var rankedDay = day
            var rankedBlocks: [GeneratedTimeBlock] = []

            for block in day.timeBlocks {

                let resolved = await withTaskGroup(
                    of: (GeneratedActivity, CLLocationCoordinate2D?).self
                ) { group -> [(GeneratedActivity, CLLocationCoordinate2D?)] in

                    for option in block.options {
                        group.addTask {
                            (
                                option,
                                await resolveCoordinate(
                                    for: option.location,
                                    near: tripCenter
                                )
                            )
                        }
                    }

                    var results: [(GeneratedActivity, CLLocationCoordinate2D?)] = []

                    for await result in group {
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

                var rankedBlock = block
                rankedBlock.options = sorted.map(\.0)
                rankedBlocks.append(rankedBlock)

                if let closest = sorted.first?.1 {
                    anchor = closest
                }
            }

            rankedDay.timeBlocks = rankedBlocks
            rankedDays.append(rankedDay)
        }

        return rankedDays
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
