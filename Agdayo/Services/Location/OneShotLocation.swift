import CoreLocation
import Observation

/// Asks for one location fix, only when the person has already allowed it
/// (or taps to allow it). Used by the Today card to time the trip to the
/// next stop from where you actually are.
@MainActor
@Observable
final class OneShotLocation: NSObject, CLLocationManagerDelegate {
    private(set) var authorizationStatus: CLAuthorizationStatus
    private let manager = CLLocationManager()
    private var waiting: [CheckedContinuation<CLLocationCoordinate2D?, Never>] = []

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isAllowed: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var canAsk: Bool { authorizationStatus == .notDetermined }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    /// The current position, or nil when not allowed or no fix within 10 s.
    func current() async -> CLLocationCoordinate2D? {
        guard isAllowed else { return nil }
        return await withCheckedContinuation { continuation in
            waiting.append(continuation)
            if waiting.count == 1 { manager.requestLocation() }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(10))
                self?.finish(nil)
            }
        }
    }

    private func finish(_ coordinate: CLLocationCoordinate2D?) {
        let pending = waiting
        waiting.removeAll()
        pending.forEach { $0.resume(returning: coordinate) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorizationStatus = status }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last?.coordinate
        Task { @MainActor in self.finish(coordinate) }
    }

    /// Required by `requestLocation()`; a failed fix just means no position.
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }
}
