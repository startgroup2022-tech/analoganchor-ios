import Foundation
import CoreLocation
import AnalogAnchorKit

/// Minimal CoreLocation wrapper.
///
/// Requests the *least* privilege required: `whenInUse` only. Location is used
/// to (a) compute prayer times and (b) verify sanctuary proximity. No continuous
/// background location is requested in Phase 2.
@MainActor
final class LocationService: NSObject, ObservableObject {

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var lastLocation: CLLocation?

    private let manager = CLLocationManager()
    private var oneShotContinuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    /// Asks for the minimal permission. Call this only when the user actually
    /// opens a location-dependent feature (radar / prayer times).
    func requestAuthorization() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// One-shot location fetch for prayer-times calculation.
    func currentLocation() async -> CLLocation? {
        if let lastLocation, abs(lastLocation.timestamp.timeIntervalSinceNow) < 60 {
            return lastLocation
        }
        guard isAuthorized else { return nil }
        return await withCheckedContinuation { continuation in
            oneShotContinuation = continuation
            manager.requestLocation()
        }
    }

    /// Great-circle distance in metres (Haversine), matching the Android helper.
    static func distanceMeters(from a: (lat: Double, lng: Double), to b: (lat: Double, lng: Double)) -> Double {
        let earthRadius = 6_371_000.0
        let dLat = (b.lat - a.lat) * .pi / 180
        let dLng = (b.lng - a.lng) * .pi / 180
        let lat1 = a.lat * .pi / 180
        let lat2 = b.lat * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + sin(dLng / 2) * sin(dLng / 2) * cos(lat1) * cos(lat2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }
}

// MARK: - LocationProviding

extension LocationService: LocationProviding {
    /// Domain-facing one-shot coordinate access; `nil` when unauthorized or the
    /// fix fails.
    func currentCoordinate() async -> (latitude: Double, longitude: Double)? {
        guard let location = await currentLocation() else { return nil }
        return (location.coordinate.latitude, location.coordinate.longitude)
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.lastLocation = location
            self.oneShotContinuation?.resume(returning: location)
            self.oneShotContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.oneShotContinuation?.resume(returning: nil)
            self.oneShotContinuation = nil
        }
    }
}
