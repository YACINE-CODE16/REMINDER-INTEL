import CoreLocation
import MapKit
import SwiftData

/// Where the prayer times are computed: one CoreLocation fix when the module is switched on
/// (or on "Actualiser la position"), or a city picked with MKLocalSearch.
@MainActor
enum PrayerLocator {
    struct Place: Sendable, Identifiable, Equatable {
        var name: String
        var detail: String?
        var latitude: Double
        var longitude: Double

        var id: String { "\(name)-\(latitude)-\(longitude)" }
    }

    /// One location fix, nil if refused, restricted or not found within 15 s.
    static func currentPlace() async -> Place? {
        await withTaskGroup(of: Place?.self) { group in
            group.addTask { await locate() }
            group.addTask {
                try? await Task.sleep(for: .seconds(15))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private static func locate() async -> Place? {
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                    return nil
                }
                guard let location = update.location else { continue }
                let name = await cityName(for: location) ?? "Position actuelle"
                return Place(name: name, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            }
        } catch {
            return nil
        }
        return nil
    }

    private static func cityName(for location: CLLocation) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first
        else { return nil }
        return item.addressRepresentations?.cityName ?? item.name
    }

    /// Cities matching `query` (MapKit search, on Apple's servers like Plans).
    static func search(_ query: String) async -> [Place] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = .address
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        var places: [Place] = []
        for item in response.mapItems {
            let coordinate = item.location.coordinate
            let name = item.addressRepresentations?.cityName ?? item.name ?? trimmed
            let place = Place(name: name, detail: item.addressRepresentations?.regionName, latitude: coordinate.latitude, longitude: coordinate.longitude)
            if !places.contains(where: { $0.name == place.name && $0.detail == place.detail }) {
                places.append(place)
            }
        }
        return places
    }

    /// Saves the place in the settings and rebuilds times, notifications and widget.
    static func apply(_ place: Place, to settings: PrayerSettings) {
        settings.latitude = place.latitude
        settings.longitude = place.longitude
        settings.cityName = place.name
        settings.hasLocation = true
        try? settings.modelContext?.save()
        PrayerService.shared.refresh()
    }
}
