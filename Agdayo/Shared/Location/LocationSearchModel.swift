import Foundation
import MapKit
import Observation

/// Wraps MKLocalSearchCompleter for as-you-type autocomplete and MKLocalSearch
/// to resolve a chosen completion into a real MKMapItem (coordinate + address).
/// Region bias only — no location permission or live GPS is required.
@MainActor
@Observable
final class LocationSearchModel: NSObject {
    private(set) var results: [MKLocalSearchCompletion] = []

    private let completer: MKLocalSearchCompleter

    override init() {
        completer = MKLocalSearchCompleter()
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
    }

    var queryFragment: String = "" {
        didSet {
            completer.queryFragment = queryFragment
        }
    }

    func setRegionBias(center: CLLocationCoordinate2D, radiusMeters: CLLocationDistance = 100_000) {
        completer.region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: radiusMeters,
            longitudinalMeters: radiusMeters
        )
    }

    func clearResults() {
        results = []
    }

    func resolve(_ completion: MKLocalSearchCompletion) async throws -> MKMapItem {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        guard let item = response.mapItems.first else {
            throw LocationSearchError.noResults
        }
        return item
    }
}

enum LocationSearchError: Error {
    case noResults
}

extension LocationSearchModel: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let newResults = completer.results
        Task { @MainActor in
            self.results = newResults
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.results = []
        }
    }
}
