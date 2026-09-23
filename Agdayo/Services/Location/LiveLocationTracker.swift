import CoreLocation
import Observation

/// Thin CLLocationManager wrapper for foreground-only live location sharing on
/// a trip's map. Deliberately coarse (100m accuracy, 25m distance filter) —
/// this is "which member is where on the trip," not turn-by-turn navigation.
@MainActor
@Observable
final class LiveLocationTracker: NSObject, CLLocationManagerDelegate {
    private(set) var authorizationStatus: CLAuthorizationStatus

    private let manager = CLLocationManager()
    private var onUpdate: ((CLLocationCoordinate2D) -> Void)?

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 25
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func start(onUpdate: @escaping (CLLocationCoordinate2D) -> Void) {
        self.onUpdate = onUpdate
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        onUpdate = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in
            self.onUpdate?(coordinate)
        }
    }
}
