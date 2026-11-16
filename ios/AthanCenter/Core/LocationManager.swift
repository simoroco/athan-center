import Foundation
import CoreLocation

// MARK: - Place — resolved city (name + coordinates + IANA timezone)

struct Place {
    let city: String
    let lat: Double
    let lon: Double
    let tz: String
}

// MARK: - LocationManager — one-shot position. Never tracked in the background.
// Every path (success, denial, failure, timeout) resumes the continuation exactly once.

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var resolving = false
    @Published var error: String? = nil

    nonisolated let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Place?, Never>?
    private var timeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer   // city-level is enough
    }

    /// Asks permission if needed, then resolves the current position to a city. nil on any failure (see `error`).
    func resolve() async -> Place? {
        guard continuation == nil else { return nil }
        error = nil
        resolving = true
        return await withCheckedContinuation { (c: CheckedContinuation<Place?, Never>) in
            continuation = c
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled else { return }
                self?.finish(nil, error: "Locating took too long. Try again or enter your city manually.")
            }
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()
            case .denied, .restricted:
                finish(nil, error: "Location access denied — enable it in iOS Settings, or enter your city manually.")
            default: manager.requestLocation()
            }
        }
    }

    private func finish(_ place: Place?, error: String? = nil) {
        guard let c = continuation else { return }
        continuation = nil
        timeoutTask?.cancel()
        resolving = false
        self.error = error
        c.resume(returning: place)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard continuation != nil else { return }   // ignore the initial callback / unsolicited changes
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
            case .denied, .restricted:
                finish(nil, error: "Location access denied — enable it in iOS Settings, or enter your city manually.")
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            guard continuation != nil else { return }
            var city = "My Location"
            var tz = TimeZone.current.identifier
            if let mark = try? await CLGeocoder().reverseGeocodeLocation(loc).first {
                city = mark.locality ?? mark.administrativeArea ?? city
                tz = mark.timeZone?.identifier ?? tz
            }
            finish(Place(city: city, lat: loc.coordinate.latitude, lon: loc.coordinate.longitude, tz: tz))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError err: Error) {
        Task { @MainActor in
            finish(nil, error: "Could not determine your position. Try again or enter your city manually.")
        }
    }

    // MARK: Manual city → coordinates

    static func search(city: String) async -> Place? {
        let q = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty,
              let mark = try? await CLGeocoder().geocodeAddressString(q).first,
              let loc = mark.location else { return nil }
        return Place(city: mark.locality ?? q, lat: loc.coordinate.latitude, lon: loc.coordinate.longitude,
                     tz: mark.timeZone?.identifier ?? TimeZone.current.identifier)
    }
}
