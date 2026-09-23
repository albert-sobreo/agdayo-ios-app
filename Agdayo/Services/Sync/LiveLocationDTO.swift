import Foundation

/// One member's last-known position for a trip's live-location sharing —
/// `trips/{tripID}/liveLocations/{uid}`, always a full overwrite (no history).
struct LiveLocationDTO: Codable {
    var uid: String
    var latitude: Double
    var longitude: Double
    var updatedAt: Date
}
