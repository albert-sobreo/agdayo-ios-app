import CoreLocation
import Observation

/// Thin CLLocationManager wrapper for foreground-only live location sharing on
/// a trip's map. Deliberately coarse (100m accuracy) — this is "which member
/// is where on the trip," not turn-by-turn navigation.
///
/// Takes a single-shot `requestLocation()` fix on a repeating timer rather
/// than `startUpdatingLocation()` — the GPS radio powers down between fixes
/// instead of streaming continuously, which is the actual battery cost of
/// live sharing. Trades off live-in-a-moving-car smoothness for battery,
/// which is the right call for "where's everyone roughly right now."
@MainActor
@Observable
final class LiveLocationTracker: NSObject, CLLocationManagerDelegate {
    private(set) var authorizationStatus: CLAuthorizationStatus

    private let manager = CLLocationManager()
    private var onUpdate: ((CLLocationCoordinate2D) -> Void)?
    private var timer: Timer?

    private let updateInterval: TimeInterval = 120

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func start(onUpdate: @escaping (CLLocationCoordinate2D) -> Void) {
        self.onUpdate = onUpdate
        manager.requestLocation()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.manager.requestLocation() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
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

    /// `requestLocation()` requires this method to be implemented at all —
    /// its absence is a hard runtime crash (`NSInternalInconsistencyException`),
    /// unlike `startUpdatingLocation()` where it's optional. A single fix
    /// failing (no signal, momentary GPS hiccup) just gets picked up on the
    /// next timer tick, so there's nothing to do here.
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
