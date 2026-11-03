import Testing
import WingspotCore

struct DistanceVector: Decodable, Sendable, CustomTestStringConvertible {
    struct Point: Decodable, Sendable {
        let code: String
        let latitude: Double
        let longitude: Double
        var coordinate: GeoCoordinate { GeoCoordinate(latitude: latitude, longitude: longitude) }
    }

    let from: Point
    let to: Point
    let expectedKm: Double
    let crossesEquator: Bool
    let crossesAntimeridian: Bool

    var testDescription: String { "\(from.code)–\(to.code)" }
}

struct DistanceVectors: Decodable {
    let toleranceKm: Double
    let cases: [DistanceVector]
}

@Suite struct GreatCircleTests {
    static let vectors = TestVectors.load("distances", as: DistanceVectors.self)

    @Test(arguments: vectors.cases)
    func matchesVector(_ vector: DistanceVector) {
        let a = vector.from.coordinate, b = vector.to.coordinate
        let distance = GreatCircle.distanceKm(from: a, to: b)
        #expect(abs(distance - vector.expectedKm) <= Self.vectors.toleranceKm)
        #expect(GreatCircle.crossesEquator(from: a, to: b) == vector.crossesEquator)
        #expect(GreatCircle.crossesAntimeridian(from: a, to: b) == vector.crossesAntimeridian)
    }

    @Test(arguments: vectors.cases)
    func isSymmetric(_ vector: DistanceVector) {
        let a = vector.from.coordinate, b = vector.to.coordinate
        #expect(abs(GreatCircle.distanceKm(from: a, to: b) - GreatCircle.distanceKm(from: b, to: a)) < 0.001)
    }
}
