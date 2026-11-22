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
