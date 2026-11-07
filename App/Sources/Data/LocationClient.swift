import CoreLocation
import Foundation

/// Why there's no position
enum LocationError: Error {
    /// Location is turned off on the phone
    case disabled
    /// The app isn't allowed to read the location
    case denied
    /// No fix came, e.g. indoors, and no recent position to fall back on
    case noFix
}

/// One-shot current location, asking for the permission when it hasn't been asked yet
@MainActor
final class LocationClient: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var permissionWaiters: [CheckedContinuation<Void, Never>] = []
    private var fixWaiters: [CheckedContinuation<CLLocation?, Never>] = []

    /// How long to wait for a fresh fix before settling for the last known position
    private let fixTimeout: UInt64 = 10_000_000_000
    /// The oldest last known position still trusted
    private let maxLastKnownAge: TimeInterval = 120

    /// Sets itself as the location manager's delegate, asking for the best accuracy
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    /// The app may read the location
    var hasPermission: Bool {
        let status = manager.authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }

    /// The user said no, or the phone doesn't allow it: asking again shows nothing
    var isDenied: Bool {
        let status = manager.authorizationStatus
        return status == .denied || status == .restricted
    }

    /// Asks for the permission if it hasn't been asked yet; true when it's granted
    func requestPermission() async -> Bool {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { continuation in
                permissionWaiters.append(continuation)
                manager.requestWhenInUseAuthorization()
            }
        }
        return hasPermission
    }

    /// Where the phone is. Asks for the permission first if needed. Indoors a fresh fix can take very long
    /// or never come, so after 10 seconds it settles for a position from the last two minutes.
    func current() async throws -> Coords {
        guard await requestPermission() else { throw LocationError.denied }
        guard CLLocationManager.locationServicesEnabled() else { throw LocationError.disabled }

        let fix: CLLocation? = await withCheckedContinuation { continuation in
            fixWaiters.append(continuation)
            manager.requestLocation()
            Task { [weak self, fixTimeout] in
                try? await Task.sleep(nanoseconds: fixTimeout)
                self?.finishFix(nil)
            }
        }
        if let fix { return Coords(lat: fix.coordinate.latitude, lng: fix.coordinate.longitude, accuracy: fix.horizontalAccuracy) }
        if let last = manager.location, -last.timestamp.timeIntervalSinceNow <= maxLastKnownAge {
            return Coords(lat: last.coordinate.latitude, lng: last.coordinate.longitude, accuracy: last.horizontalAccuracy)
        }
        throw LocationError.noFix
    }

    private func finishFix(_ location: CLLocation?) {
        let waiters = fixWaiters
        fixWaiters = []
        waiters.forEach { $0.resume(returning: location) }
    }

    private func finishPermission() {
        let waiters = permissionWaiters
        permissionWaiters = []
        waiters.forEach { $0.resume() }
    }

    /// The permission was answered: wakes up whoever is waiting for it
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status != .notDetermined { self.finishPermission() }
        }
    }

    /// A fix came: hands the newest one to whoever is waiting
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in self.finishFix(last) }
    }

    /// No fix: whoever is waiting gets nothing and falls back on the last known position
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finishFix(nil) }
    }
}
