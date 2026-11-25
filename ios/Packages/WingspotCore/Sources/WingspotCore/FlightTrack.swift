import Foundation

/// Maths for a flown track: a list of positions in the order they were flown. It knows nothing about where the
/// positions came from, so any source can use it. Shared with the Android app and checked against
/// `contracts/test-vectors/tracks.json`.
public enum FlightTrack {
    /// The latitude where Web Mercator ends.
    private static let mercatorLimit = 85.05
    private static let earthRadiusMeters = GreatCircle.earthRadiusKm * 1000

    /// The length in kilometres: the haversine distances between neighbouring positions added up. The date line needs no
    /// special care, because the haversine of 358° and 2° apart is the same.
    public static func lengthKm(_ points: [GeoCoordinate]) -> Double {
        guard points.count > 1 else { return 0 }
        var total = 0.0
        for index in 1..<points.count { total += GreatCircle.distanceKm(from: points[index - 1], to: points[index]) }
        return total
    }

    /// The same positions with longitudes that never jump: each one is shifted by a multiple of 360° to lie closest to
    /// the one before. A flight across the date line then has longitudes above 180° (or below -180°) instead of a jump.
    public static func unwrapped(_ points: [GeoCoordinate]) -> [GeoCoordinate] {
        guard var previous = points.first?.longitude else { return [] }
        var result = [points[0]]
        for point in points.dropFirst() {
            let shifted = point.longitude + ((previous - point.longitude) / 360).rounded() * 360
            result.append(GeoCoordinate(latitude: point.latitude, longitude: shifted))
            previous = shifted
        }
        return result
    }

    /// Whether the track passes the 180° meridian.
    public static func crossesAntimeridian(_ points: [GeoCoordinate]) -> Bool {
        zip(points, points.dropFirst()).contains { GreatCircle.crossesAntimeridian(from: $0, to: $1) }
    }

    /// A lighter track that looks the same on a map. The longitudes are unwrapped first, so the result is one continuous
    /// line. The first and last position are kept. Positions are dropped with Ramer–Douglas–Peucker on Web Mercator
    /// metres, with the tolerance scaled by cos(latitude), so `toleranceMeters` means metres on the ground everywhere.
    public static func simplified(_ points: [GeoCoordinate], toleranceMeters: Double) -> [GeoCoordinate] {
        let track = unwrapped(points)
        guard track.count > 2 else { return track }
        let plane = track.map(project)
        var keep = [Bool](repeating: false, count: track.count)
        keep[0] = true
        keep[track.count - 1] = true
        var ranges = [(0, track.count - 1)]
        while let (first, last) = ranges.popLast() {
            var worst = -1.0, worstIndex = -1
            if last - first > 1 {
                for index in (first + 1)..<last {
                    let ground = distance(plane[index], toSegmentFrom: plane[first], to: plane[last])
                        * cos(clampedLatitude(track[index].latitude) * .pi / 180)
                    if ground > worst { worst = ground; worstIndex = index }
                }
            }
            if worstIndex >= 0, worst > toleranceMeters {
                keep[worstIndex] = true
                ranges.append((first, worstIndex))
                ranges.append((worstIndex, last))
            }
        }
        return track.indices.filter { keep[$0] }.map { track[$0] }
    }

    /// The smallest box around the track, with longitudes unwrapped. Nil for an empty track.
    public static func boundingBox(_ points: [GeoCoordinate]) -> (minLatitude: Double, minLongitude: Double, maxLatitude: Double, maxLongitude: Double)? {
        let track = unwrapped(points)
        guard let first = track.first else { return nil }
        var box = (minLatitude: first.latitude, minLongitude: first.longitude, maxLatitude: first.latitude, maxLongitude: first.longitude)
        for point in track {
            box.minLatitude = min(box.minLatitude, point.latitude)
            box.maxLatitude = max(box.maxLatitude, point.latitude)
            box.minLongitude = min(box.minLongitude, point.longitude)
            box.maxLongitude = max(box.maxLongitude, point.longitude)
        }
        return box
    }

    /// How much longer the flown way was than the great circle: the extra kilometres and the extra as a percentage of
    /// the great circle. Nil when there is no great-circle distance to compare with.
    public static func detour(flownKm: Double, greatCircleKm: Double) -> (extraKm: Double, percent: Double)? {
        guard greatCircleKm > 0 else { return nil }
        let extra = flownKm - greatCircleKm
        return (extra, extra / greatCircleKm * 100)
    }

    /// A gap this long between two neighbouring positions (over the ocean, for example) is drawn as a straight line, so the flown distance of
    /// a route with such a gap is an estimate, a little too short (#239). The number is a first guess, to be tuned with real files.
    public static let estimatedGapKm = 200.0

    /// The longest distance between two neighbouring positions, in kilometres. 0 for fewer than two positions.
    public static func largestGapKm(_ points: [GeoCoordinate]) -> Double {
        var largest = 0.0
        for (a, b) in zip(points, points.dropFirst()) { largest = max(largest, GreatCircle.distanceKm(from: a, to: b)) }
        return largest
    }

    /// Whether the route has a gap of at least `estimatedGapKm`, so its flown distance is an estimate.
    public static func isEstimated(_ points: [GeoCoordinate]) -> Bool {
        largestGapKm(points) >= estimatedGapKm
    }

    /// What a flight page shows about a flown route: its length in whole kilometres and, when it is clearly longer than the
    /// airport-to-airport distance, how much more that is (kilometres and percent). Nil for fewer than two positions.
    public static func flownRoute(_ points: [GeoCoordinate], greatCircleKm: Int?) -> FlownRoute? {
        guard points.count >= 2 else { return nil }
        let flown = lengthKm(points)
        let flownKm = Int(flown.rounded())
        guard let greatCircleKm, let detour = detour(flownKm: flown, greatCircleKm: Double(greatCircleKm)), detour.extraKm >= 1 else {
            return FlownRoute(flownKm: flownKm, extraKm: 0, percent: 0)
        }
        return FlownRoute(flownKm: flownKm, extraKm: Int(detour.extraKm.rounded()), percent: Int(detour.percent.rounded()))
    }

    private static func clampedLatitude(_ latitude: Double) -> Double {
        min(mercatorLimit, max(-mercatorLimit, latitude))
    }

    private static func project(_ point: GeoCoordinate) -> (x: Double, y: Double) {
        let latitude = clampedLatitude(point.latitude) * .pi / 180
        return (earthRadiusMeters * point.longitude * .pi / 180, earthRadiusMeters * log(tan(.pi / 4 + latitude / 2)))
    }

    private static func distance(_ p: (x: Double, y: Double), toSegmentFrom a: (x: Double, y: Double), to b: (x: Double, y: Double)) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - a.x - t * dx, p.y - a.y - t * dy)
    }
}

/// A flown route as the flight page shows it. `extraKm` and `percent` are 0 when there is no clear detour.
public struct FlownRoute: Equatable, Sendable {
    public let flownKm: Int
    public let extraKm: Int
    public let percent: Int

    public init(flownKm: Int, extraKm: Int, percent: Int) {
        self.flownKm = flownKm
        self.extraKm = extraKm
        self.percent = percent
    }
}

/// What the profile says about the flights that have a flown route: how many, the real distance flown, the longest
/// route and the biggest detour compared with the airport-to-airport distance.
public struct FlownRouteStats: Equatable, Sendable {
    public let routes: Int
    public let totalKm: Int
    public let longestKm: Int
    /// 0 when no route is clearly longer than its airport-to-airport distance.
    public let biggestDetourKm: Int

    public init(routes: Int, totalKm: Int, longestKm: Int, biggestDetourKm: Int) {
        self.routes = routes
        self.totalKm = totalKm
        self.longestKm = longestKm
        self.biggestDetourKm = biggestDetourKm
    }

    /// - Parameter flights: for each flight with a route, its flown length and, when known, the great-circle distance
    ///   between its airports. Nil for no flights.
    public static func of(_ flights: [(flownKm: Double, greatCircleKm: Double?)]) -> FlownRouteStats? {
        guard !flights.isEmpty else { return nil }
        let detour = flights.compactMap { flight in flight.greatCircleKm.map { flight.flownKm - $0 } }.max() ?? 0
        return FlownRouteStats(
            routes: flights.count,
            totalKm: Int(flights.reduce(0) { $0 + $1.flownKm }.rounded()),
            longestKm: Int((flights.map(\.flownKm).max() ?? 0).rounded()),
            biggestDetourKm: detour >= 1 ? Int(detour.rounded()) : 0
        )
    }
}

/// The real distance flown in one year, from the flights that have a route (#239).
public struct YearDistance: Equatable, Sendable {
    public let year: Int
    public let routes: Int
    public let km: Int

    public init(year: Int, routes: Int, km: Int) {
        self.year = year
        self.routes = routes
        self.km = km
    }
}

extension FlownRouteStats {
    /// The flown distance per year, newest year first. A year is rounded once from the sum, so the years need not add up to the total
    /// by a kilometre or two.
    public static func byYear(_ flights: [(flownKm: Double, year: Int)]) -> [YearDistance] {
        var kilometres = [Int: Double]()
        var count = [Int: Int]()
        for flight in flights {
            kilometres[flight.year, default: 0] += flight.flownKm
            count[flight.year, default: 0] += 1
        }
        return kilometres.keys.sorted(by: >).map { year in
            YearDistance(year: year, routes: count[year] ?? 0, km: Int((kilometres[year] ?? 0).rounded()))
        }
    }
}
