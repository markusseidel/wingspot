import Foundation
import Testing
import WingspotCore
@testable import ReferenceData

/// Checks search quality on a real snapshot. To run these, build one with backend/refdata-pipeline and pass its path:
/// `WINGSPOT_REFDATA_PATH=/path/to/refdata.sqlite swift test`
@Suite(.enabled(if: ProcessInfo.processInfo.environment["WINGSPOT_REFDATA_PATH"] != nil))
struct RealSnapshotTests {
    private let database = try! ReferenceDatabase(path: ProcessInfo.processInfo.environment["WINGSPOT_REFDATA_PATH"]!)

    @Test(arguments: [
        ("a388", "A388"), ("crj900", "CRJ9"), ("an124", "A124"), ("ec135", "EC35"), ("h135", "EC35"),
        ("e175", "E75L"), ("md82", "MD82"), ("typhoon", "EUFI"),
    ])
    func findsCommonTypes(text: String, code: String) async throws {
        let results = try await database.searchTypes(text)
        #expect(results.contains { $0.icaoCode == code }, "\(text) should find \(code)")
    }

    @Test(arguments: [("fra", "FRA"), ("wien", "VIE"), ("münchen", "MUC"), ("munich", "MUC"), ("heathrow", "LHR")])
    func theExpectedAirportComesFirst(text: String, iata: String) async throws {
        let results = try await database.searchAirports(text)
        #expect(results.first?.iata == iata, "\(text) found \(results.first?.name ?? "nothing")")
    }

    @Test func suggestsFrankfurtOnTheAirportFence() async throws {
        let position = GeoCoordinate(latitude: 50.03, longitude: 8.57)
        #expect(try await database.nearestAirport(to: position)?.iata == "FRA")
    }

    @Test func searchStaysFastOnTheFullData() async throws {
        let clock = ContinuousClock()
        let elapsed = try await clock.measure { _ = try await database.searchAirports("a") }
        #expect(elapsed < .milliseconds(200), "took \(elapsed)")
    }
}
