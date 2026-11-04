import CoreLocation
import WingspotCore

enum LocationProvider {
    /// One position for suggesting an airport, or `nil` if location is off or denied. A check-in never waits for it.
    static func currentPosition() async -> GeoCoordinate? {
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                    return nil
                }
                if let location = update.location, location.horizontalAccuracy >= 0, location.horizontalAccuracy < 1_000 {
                    return GeoCoordinate(
                        latitude: location.coordinate.latitude, longitude: location.coordinate.longitude
                    )
                }
            }
        } catch {
            return nil
        }
        return nil
    }
}
