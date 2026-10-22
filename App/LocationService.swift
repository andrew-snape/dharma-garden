import CoreLocation
import Foundation
import WeedsCore

/// Gets the Mac's location once when asked, then names the town it is in. Permission is requested only
/// when the user has turned on "Use my location". Any failure (denied, no fix, offline) returns nil, so the
/// caller keeps the place it already has.
@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var status: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    /// Callers waiting for one fix. Several can wait at once; they all get the same answer.
    private var waiting: [CheckedContinuation<CLLocation?, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        // A town is all the garden needs, so coarse accuracy is enough (and more private).
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        status = manager.authorizationStatus
    }

    /// True when the user has refused location for Garden in System Settings.
    var isDenied: Bool { status == .denied || status == .restricted }

    /// The town the Mac is in right now, or nil when location is unavailable.
    func currentTown() async -> Town? {
        guard let location = await fix() else { return nil }
        return await townName(for: location)
    }

    // MARK: One fix

    private func fix() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            waiting.append(continuation)
            if waiting.count == 1 { startRequest() }
        }
    }

    private func startRequest() {
        guard CLLocationManager.locationServicesEnabled() else { finish(nil); return }
        switch manager.authorizationStatus {
        case .notDetermined:
            // The delegate carries on when the user answers the permission prompt.
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            finish(nil)
        default:
            manager.requestLocation()
        }
    }

    private func finish(_ location: CLLocation?) {
        let pending = waiting
        waiting = []
        for continuation in pending { continuation.resume(returning: location) }
    }

    private func townName(for location: CLLocation) async -> Town {
        let coordinate = location.coordinate
        let mark = (try? await CLGeocoder().reverseGeocodeLocation(location))?.first
        return Town(name: mark?.locality ?? mark?.subAdministrativeArea ?? "Your location",
                    latitude: coordinate.latitude, longitude: coordinate.longitude,
                    admin1: mark?.administrativeArea, country: mark?.country)
    }

    // MARK: CLLocationManagerDelegate (called on arbitrary threads, so hop to the main actor)

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let current = manager.authorizationStatus
        Task { @MainActor in
            self.status = current
            if !self.waiting.isEmpty, current != .notDetermined { self.startRequest() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let latest = locations.last
        Task { @MainActor in self.finish(latest) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }
}
