import Foundation
import CoreLocation
import MapKit

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

    /// Asks for location access once. iOS only shows the prompt while the
    /// status is undetermined, so later calls are silent no-ops — the
    /// permission is re-asked only through `resolve()` (the locate button).
    func requestPermissionIfNeeded() {
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
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

// MARK: - CitySearchCompleter — live city suggestions while typing
// (MKLocalSearchCompleter throttles/rate-limits requests internally).

@MainActor
final class CitySearchCompleter: NSObject, ObservableObject {
    @Published private(set) var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.resultTypes = .address
        completer.delegate = self
    }

    /// Feed every keystroke; suggestions appear from 2 characters.
    func update(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.count < 2 {
            completer.queryFragment = ""
            results = []
        } else if completer.queryFragment != q {
            completer.queryFragment = q
        }
    }

    func clear() {
        completer.queryFragment = ""
        results = []
    }

    /// Resolves a picked suggestion into a Place (coordinates + timezone).
    static func resolve(_ completion: MKLocalSearchCompletion) async -> Place? {
        let request = MKLocalSearch.Request(completion: completion)
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first,
              let loc = item.placemark.location else { return nil }
        return Place(city: item.placemark.locality ?? completion.title,
                     lat: loc.coordinate.latitude, lon: loc.coordinate.longitude,
                     tz: item.placemark.timeZone?.identifier ?? TimeZone.current.identifier)
    }
}

extension CitySearchCompleter: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let found = completer.results
        Task { @MainActor in self.results = found }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}
}
