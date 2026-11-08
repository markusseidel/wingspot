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

@Test func findsAnAirportByID() async throws {
    let database = try database()
    let frankfurt = try #require(try await database.searchAirports("FRA").first)
    #expect(try await database.airport(id: frankfurt.id) == frankfurt)
    #expect(try await database.airport(id: -1) == nil)
}

@Test func findsAnAirportByItsIATACode() async throws {
    let database = try database()
    let frankfurt = try #require(try await database.airport(iata: "fra"))
    #expect(frankfurt.iata == "FRA")
    #expect(try await database.airport(iata: "ZZZ") == nil)
}

@Test func airportsNearbyAreSortedByDistanceAndSkipSmallFields() async throws {
    let database = try database()
    let nearFrankfurt = try await database.airports(near: GeoCoordinate(latitude: 50.0, longitude: 8.6), withinKm: 100)
    #expect(nearFrankfurt.map(\.airport.id) == [3], "the airfield and the heliport have no IATA code or are heliports")
    #expect(nearFrankfurt.first.map { $0.distanceKm < 10 } == true)

    let wide = try await database.airports(near: GeoCoordinate(latitude: 49.0, longitude: 12.0), withinKm: 1000)
    #expect(wide.map(\.airport.id) == [3, 1], "Frankfurt is closer than Vienna from here")
    #expect(wide[0].distanceKm < wide[1].distanceKm)
    #expect(try await database.airports(near: GeoCoordinate(latitude: 49.0, longitude: 12.0), withinKm: 1000, limit: 1).count == 1)
}

@Test func nothingIsNearInTheMiddleOfTheOcean() async throws {
    #expect(try await database().airports(near: GeoCoordinate(latitude: 0, longitude: 0)).isEmpty)
}
