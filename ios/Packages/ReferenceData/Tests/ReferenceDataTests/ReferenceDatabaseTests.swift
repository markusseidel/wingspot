import Foundation
import Testing
import WingspotCore
@testable import ReferenceData

private func database() throws -> ReferenceDatabase {
    try ReferenceDatabase(path: Fixture.makeDatabase().path)
}

@Test func opensTheContractSchemaAndReadsItsVersion() throws {
    #expect(try database().dataVersion == "test-1")
}

@Test func refusesAnUnsupportedSchema() throws {
    let url = try Fixture.makeDatabase(userVersion: 99)
    #expect(throws: ReferenceDataError.unsupportedSchema(99)) {
        try ReferenceDatabase(path: url.path)
    }
}

@Test func anExactTypeCodeComesFirst() async throws {
    let results = try await database().searchTypes("b738")
    #expect(results.first?.icaoCode == "B738")
}

@Test func findsTypesByMakerAndModel() async throws {
    let results = try await database().searchTypes("boeing 737")
    #expect(Set(results.map(\.icaoCode)) == ["B738", "B38M"])
}

@Test(arguments: ["crj900", "crj 900", "CRJ-900", "crj9"])
func findsHyphenatedNamesHoweverTheyAreTyped(text: String) async throws {
    let results = try await database().searchTypes(text)
    #expect(results.map(\.icaoCode) == ["CRJ9"])
}

@Test func emptyOrSymbolOnlySearchesFindNothing() async throws {
    #expect(try await database().searchTypes("  ").isEmpty)
    #expect(try await database().searchAirports("\"*(-").isEmpty)
}

@Test func largeAirportsRankFirst() async throws {
    let results = try await database().searchAirports("Wien")
    #expect(results.map(\.id) == [1, 2])
}

@Test func anExactAirportCodeComesFirst() async throws {
    let results = try await database().searchAirports("fra")
    #expect(results.first?.iata == "FRA")
}

@Test func nearestPrefersTheMajorAirportOverACloserAirfield() async throws {
    let nearEgelsbach = GeoCoordinate(latitude: 49.97, longitude: 8.63)
    #expect(try await database().nearestAirport(to: nearEgelsbach)?.iata == "FRA")
}

@Test func nearestIgnoresHeliports() async throws {
    let atHeliport = GeoCoordinate(latitude: 50.04, longitude: 8.58)
    #expect(try await database().nearestAirport(to: atHeliport)?.id == 3)
}

@Test func nearestFallsBackToANearbyAirfield() async throws {
    let atAirfield = GeoCoordinate(latitude: 52.01, longitude: 10.01)
    #expect(try await database().nearestAirport(to: atAirfield)?.id == 6)
}

@Test func nearestIsNilFarFromAnyAirport() async throws {
    let atSea = GeoCoordinate(latitude: 0, longitude: 0)
    #expect(try await database().nearestAirport(to: atSea) == nil)
}
