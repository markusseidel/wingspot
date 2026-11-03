import Foundation

public struct GeoCoordinate: Hashable, Sendable, Codable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Great-circle math for flown distances and route badges (Equator Crosser, Dateline).
///
/// Shared with the Android app and checked against `contracts/test-vectors/distances.json`.
public enum GreatCircle {
    /// Mean Earth radius (IUGG).
    public static let earthRadiusKm = 6371.0088

    /// Haversine distance in kilometers.
    public static func distanceKm(from a: GeoCoordinate, to b: GeoCoordinate) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusKm * asin(min(1, sqrt(h)))
    }

    /// Whether the route connects the northern and southern hemisphere.
    public static func crossesEquator(from a: GeoCoordinate, to b: GeoCoordinate) -> Bool {
        (a.latitude < 0) != (b.latitude < 0)
    }

    /// Whether the shorter way between the two longitudes passes the 180° meridian.
    public static func crossesAntimeridian(from a: GeoCoordinate, to b: GeoCoordinate) -> Bool {
        abs(b.longitude - a.longitude) > 180
    }
}
