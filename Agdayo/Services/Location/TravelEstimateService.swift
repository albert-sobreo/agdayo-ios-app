import CoreLocation
import MapKit

struct TravelEstimate {
    let distance: CLLocationDistance
    let duration: TimeInterval
}

/// Point-to-point distance/duration between two coordinates, for the
/// itinerary's inline travel connectors — a derived display value, never
/// stored or synced. Uses `calculateETA` (not `calculate`) since only the
/// distance/time numbers are needed, not a drawn route.
enum TravelEstimateService {
    static func estimate(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, transportType: MKDirectionsTransportType) async throws -> TravelEstimate {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = transportType
        let response = try await MKDirections(request: request).calculateETA()
        return TravelEstimate(distance: response.distance, duration: response.expectedTravelTime)
    }

    /// The actual road/path geometry between two coordinates, for drawing a
    /// route line on the trip map — heavier than `estimate`, so only called
    /// where a polyline is actually needed.
    static func route(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, transportType: MKDirectionsTransportType) async throws -> MKRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = transportType
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else {
            throw TravelEstimateError.noRouteFound
        }
        return route
    }
}

enum TravelEstimateError: Error {
    case noRouteFound
}
