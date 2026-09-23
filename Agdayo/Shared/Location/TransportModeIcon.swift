import MapKit

/// Shared SF Symbol mapping, used by both the itinerary's travel connectors
/// and the trip map's route mode picker.
extension MKDirectionsTransportType {
    var sfSymbolName: String {
        switch self {
        case .walking: return "figure.walk"
        case .transit: return "bus"
        case .cycling: return "bicycle"
        default: return "car.fill"
        }
    }
}
