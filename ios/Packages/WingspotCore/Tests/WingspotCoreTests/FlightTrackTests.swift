import Testing
import WingspotCore

struct TrackVector: Decodable, Sendable, CustomTestStringConvertible {
    let name: String
    let points: [[Double]]
    let lengthKm: Double
    let crossesAntimeridian: Bool
    let unwrappedLongitudes: [Double]
    let toleranceMeters: Double
    let simplifiedCount: Int
    let simplifiedLongitudes: [Double]
    let simplifiedLatitudes: [Double]

    /// The vector's `[longitude, latitude]` pairs as coordinates.
    var coordinates: [GeoCoordinate] { points.map { GeoCoordinate(latitude: $0[1], longitude: $0[0]) } }
    var testDescription: String { name }
}

struct TrackVectors: Decodable {
    let toleranceKm: Double
    let toleranceDegrees: Double
    let cases: [TrackVector]
}

@Suite struct FlightTrackTests {
    static let vectors = TestVectors.load("tracks", as: TrackVectors.self)

    @Test(arguments: vectors.cases)
    func lengthMatchesVector(_ vector: TrackVector) {
        #expect(abs(FlightTrack.lengthKm(vector.coordinates) - vector.lengthKm) <= Self.vectors.toleranceKm)
        #expect(FlightTrack.crossesAntimeridian(vector.coordinates) == vector.crossesAntimeridian)
    }

    @Test(arguments: vectors.cases)
    func unwrappingMatchesVectorAndNeverJumps(_ vector: TrackVector) {
        let result = FlightTrack.unwrapped(vector.coordinates)
        #expect(result.count == vector.points.count)
        for (value, expected) in zip(result, vector.unwrappedLongitudes) {
            #expect(abs(value.longitude - expected) <= Self.vectors.toleranceDegrees)
        }
        for (a, b) in zip(result, result.dropFirst()) { #expect(abs(b.longitude - a.longitude) <= 180) }
        // the length does not change by unwrapping
        #expect(abs(FlightTrack.lengthKm(result) - vector.lengthKm) <= Self.vectors.toleranceKm)
    }

    @Test(arguments: vectors.cases)
    func simplifyingMatchesVector(_ vector: TrackVector) {
        let result = FlightTrack.simplified(vector.coordinates, toleranceMeters: vector.toleranceMeters)
        #expect(result.count == vector.simplifiedCount)
        for (value, index) in zip(result, vector.simplifiedLongitudes.indices) {
            #expect(abs(value.longitude - vector.simplifiedLongitudes[index]) <= Self.vectors.toleranceDegrees)
            #expect(abs(value.latitude - vector.simplifiedLatitudes[index]) <= Self.vectors.toleranceDegrees)
        }
    }

    @Test func aLighterTrackIsAboutAsLong() {
        let vector = Self.vectors.cases.first { $0.name == "Tokyo to Los Angeles, made up, across the date line" }!
        let light = FlightTrack.simplified(vector.coordinates, toleranceMeters: 5_000)
        #expect(light.count <= vector.points.count)
        #expect(abs(FlightTrack.lengthKm(light) - vector.lengthKm) / vector.lengthKm < 0.01)
    }

    @Test func theBoxCoversTheUnwrappedTrack() throws {
        let vector = Self.vectors.cases.first { $0.name == "Tokyo to Los Angeles, made up, across the date line" }!
        let box = try #require(FlightTrack.boundingBox(vector.coordinates))
        #expect(box.minLongitude == 139.78)
        #expect(abs(box.maxLongitude - 241.59) < 0.00001)
        #expect(box.minLatitude == 33.94 && box.maxLatitude == 46)
        #expect(FlightTrack.boundingBox([]) == nil)
    }

    @Test func aDetourIsTheDifferenceAndItsPercentage() throws {
        let detour = try #require(FlightTrack.detour(flownKm: 11_000, greatCircleKm: 9_000))
        #expect(detour.extraKm == 2_000)
        #expect(abs(detour.percent - 22.2222) < 0.001)
        #expect(FlightTrack.detour(flownKm: 100, greatCircleKm: 0) == nil)
    }

    @Test func fewerThanTwoPointsHaveNoLength() {
        #expect(FlightTrack.lengthKm([]) == 0)
        #expect(FlightTrack.lengthKm([GeoCoordinate(latitude: 1, longitude: 1)]) == 0)
        #expect(FlightTrack.unwrapped([]).isEmpty)
        #expect(FlightTrack.simplified([], toleranceMeters: 100).isEmpty)
    }
}

@Test func aFlownRouteIsSummarisedForTheFlightPage() {
    // A made-up route that goes from 0° to 10° east on the equator, then back 5° to the west: 15° of arc.
    let there = (0...10).map { GeoCoordinate(latitude: 0, longitude: Double($0)) }
    let back = (1...5).map { GeoCoordinate(latitude: 0, longitude: 10 - Double($0)) }
    let route = FlightTrack.flownRoute(there + back, greatCircleKm: 556)
    #expect(route?.flownKm == 1668)
    #expect(route?.extraKm == 1112)
    #expect(route?.percent == 200)
}

@Test func aRouteWithoutAClearDetourHasNoExtra() {
    let straight = (0...10).map { GeoCoordinate(latitude: 0, longitude: Double($0)) }
    #expect(FlightTrack.flownRoute(straight, greatCircleKm: 1112) == FlownRoute(flownKm: 1112, extraKm: 0, percent: 0))
    #expect(FlightTrack.flownRoute(straight, greatCircleKm: 1500) == FlownRoute(flownKm: 1112, extraKm: 0, percent: 0), "shorter than the airport figure is not a detour")
    #expect(FlightTrack.flownRoute(straight, greatCircleKm: nil)?.flownKm == 1112)
}

@Test func tooFewPositionsAreNoRoute() {
    #expect(FlightTrack.flownRoute([], greatCircleKm: 100) == nil)
    #expect(FlightTrack.flownRoute([GeoCoordinate(latitude: 1, longitude: 1)], greatCircleKm: 100) == nil)
}

@Test func routeStatsSummariseTheFlightsWithARoute() {
    let stats = FlownRouteStats.of([(flownKm: 2102, greatCircleKm: 2004), (flownKm: 504.4, greatCircleKm: 500), (flownKm: 11_486, greatCircleKm: 9_900)])
    #expect(stats == FlownRouteStats(routes: 3, totalKm: 14_092, longestKm: 11_486, biggestDetourKm: 1_586))
}

@Test func routeStatsWithoutAClearDetourOrAirportsHaveNoDetour() {
    #expect(FlownRouteStats.of([(flownKm: 100, greatCircleKm: 120)])?.biggestDetourKm == 0)
    #expect(FlownRouteStats.of([(flownKm: 100, greatCircleKm: nil)])?.biggestDetourKm == 0)
    #expect(FlownRouteStats.of([]) == nil)
}

@Test func theFlownDistanceIsSummedPerYearNewestFirst() {
    let years = FlownRouteStats.byYear([(flownKm: 1000.4, year: 2025), (flownKm: 2000.4, year: 2026), (flownKm: 500.4, year: 2025), (flownKm: 100, year: 2024)])
    #expect(years == [YearDistance(year: 2026, routes: 1, km: 2000), YearDistance(year: 2025, routes: 2, km: 1501), YearDistance(year: 2024, routes: 1, km: 100)])
    #expect(FlownRouteStats.byYear([]).isEmpty)
}

