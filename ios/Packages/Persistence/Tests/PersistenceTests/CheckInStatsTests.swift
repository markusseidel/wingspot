import Foundation
import Persistence
import SwiftData
import Testing
import WingspotCore

@MainActor
private func makeContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: LocalCheckIn.self, LocalPhoto.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return ModelContext(container)
}

private let a388 = SpottedDraft.AircraftTypeChoice(icaoCode: "A388", name: "Airbus A380-800")
private let b744 = SpottedDraft.AircraftTypeChoice(icaoCode: "B744", name: "Boeing 747-400")
private let fra = SpottedDraft.Place(airportID: 3, code: "FRA")
private let dus = SpottedDraft.Place(airportID: 7, code: "DUS")
private let jfk = SpottedDraft.Place(airportID: 9, code: "JFK")

private func all(_ context: ModelContext) throws -> [LocalCheckIn] {
    try context.fetch(FetchDescriptor<LocalCheckIn>())
}

@MainActor @Test func nothingCheckedInGivesZeros() throws {
    #expect(CheckInStats([], userID: nil) == CheckInStats())
}

@MainActor @Test func statsCountEachKindAndDistinctThings() throws {
    let context = try makeContext()
    let store = CheckInStore(context: context)
    _ = try store.saveSpotted(SpottedDraft(registration: Registration("DAIMA"), type: a388, place: fra))
    _ = try store.saveSpotted(SpottedDraft(registration: Registration("DAIMA"), type: a388, place: fra))
    _ = try store.saveSpotted(SpottedDraft(registration: Registration("DAIMB"), type: b744, place: dus))
    _ = try store.saveAirport(AirportDraft(airportID: 7, code: "DUS"))
    _ = try store.saveFlown(FlownDraft(origin: fra, destination: jfk, type: b744))

    let stats = CheckInStats(try all(context), userID: nil)
    // The flight adds a check-in at each of its airports.
    #expect(stats.checkIns == 7)
    #expect(stats.sightings == 3)
    #expect(stats.airportVisits == 3)
    #expect(stats.flights == 1)
    #expect(stats.aircraft == 2)
    #expect(stats.types == 2)
    // FRA and DUS, and JFK from the flight.
    #expect(stats.airports == 3)
    #expect(stats.airportIDs == [3, 7, 9])
}

@MainActor @Test func anotherAccountsAndRejectedCheckInsAreLeftOut() throws {
    let context = try makeContext()
    let store = CheckInStore(context: context)
    let me = UUID()
    let other = UUID()
    _ = try store.saveSpotted(SpottedDraft(registration: Registration("DAIMA")), ownerID: me)
    _ = try store.saveSpotted(SpottedDraft(registration: Registration("DAIMB")), ownerID: nil)
    _ = try store.saveSpotted(SpottedDraft(registration: Registration("DAIMC")), ownerID: other)
    let rejected = try store.saveSpotted(SpottedDraft(registration: Registration("DAIMD")), ownerID: me)
    try #require(all(context).first { $0.id == rejected.id }).syncState = SyncState.rejected.rawValue

    #expect(CheckInStats(try all(context), userID: me).checkIns == 2)
    #expect(CheckInStats(try all(context), userID: nil).checkIns == 3)
}

@MainActor @Test func collectionsListWhatWasSeenMostOftenFirst() throws {
    let context = try makeContext()
    let store = CheckInStore(context: context)
    _ = try store.saveSpotted(SpottedDraft(registration: Registration("DAIMB"), type: b744, place: dus), at: Date(timeIntervalSince1970: 1_000))
    _ = try store.saveSpotted(SpottedDraft(registration: Registration("DAIMA"), type: a388, place: fra), at: Date(timeIntervalSince1970: 2_000))
    _ = try store.saveSpotted(SpottedDraft(registration: Registration("DAIMA"), type: a388, place: fra), at: Date(timeIntervalSince1970: 3_000))
    _ = try store.saveFlown(FlownDraft(origin: fra, destination: jfk), at: Date(timeIntervalSince1970: 4_000))

    let lists = CheckInCollections(try all(context), userID: nil)
    #expect(lists.aircraft.map(\.title) == ["D-AIMA", "D-AIMB"])
    #expect(lists.aircraft.first?.count == 2)
    #expect(lists.aircraft.first?.subtitle == "Airbus A380-800")
    #expect(lists.aircraft.first?.lastSeen == Date(timeIntervalSince1970: 3_000))
    #expect(lists.types.map(\.title) == ["A388", "B744"])
    // The flight's FRA and JFK count as visits. FRA has two sightings and the flight.
    #expect(lists.airports.map(\.title) == ["FRA", "JFK", "DUS"])
    #expect(lists.airports.first?.count == 3)
}

@MainActor @Test func collectionsLeaveOutRefusedAndOtherAccountsCheckIns() throws {
    let context = try makeContext()
    let store = CheckInStore(context: context)
    let me = UUID()
    _ = try store.saveSpotted(SpottedDraft(registration: Registration("DAIMA")), ownerID: me)
    _ = try store.saveSpotted(SpottedDraft(registration: Registration("DAIMB")), ownerID: UUID())
    #expect(CheckInCollections(try all(context), userID: me).aircraft.map(\.title) == ["D-AIMA"])
}

@MainActor @Test func kilometresFlownAddsUpEachFlightFromItsAirports() throws {
    let context = try makeContext()
    let store = CheckInStore(context: context)
    _ = try store.saveFlown(FlownDraft(origin: fra, destination: jfk, type: b744))
    _ = try store.saveFlown(FlownDraft(origin: fra, destination: jfk, type: b744))
    _ = try store.saveFlown(FlownDraft(origin: fra, destination: dus, type: b744))
    let stats = CheckInStats(try all(context), userID: nil)
    // About 100 km from the equator to a degree of latitude: FRA 0,0 and JFK 1,0 are 111 km apart, DUS is not known.
    let places: [Int: GeoCoordinate] = [3: .init(latitude: 0, longitude: 0), 9: .init(latitude: 1, longitude: 0)]
    #expect(stats.kilometres { places[$0] } == 222)
    #expect(stats.kilometres { _ in nil } == 0)
}

@MainActor @Test func recentTypesOfAFlightNumberComeNewestFirstEachOnce() throws {
    let context = try makeContext()
    let store = CheckInStore(context: context)
    let a321 = SpottedDraft.AircraftTypeChoice(icaoCode: "A321", name: "Airbus A321")
    let day = 86_400.0
    let now = Date()
    for (number, type, ago) in [("LH400", b744, 3.0), ("LH400", a388, 2.0), ("LH400", b744, 1.0), ("LH401", a321, 1.0)] {
        _ = try store.saveFlown(FlownDraft(origin: fra, destination: jfk, flightNumber: number, type: type), at: now - ago * day)
    }
    let types = try store.recentTypes(forFlight: " lh400 ", userID: nil)
    #expect(types.map(\.icaoCode) == ["B744", "A388"])
    #expect(try store.recentTypes(forFlight: "", userID: nil).isEmpty)
    #expect(try store.recentTypes(forFlight: "LH999", userID: nil).isEmpty)
    // The flight being edited is not offered back.
    let newest = try #require(try all(context).filter { $0.flightNumber == "LH400" }.max { $0.occurredAt < $1.occurredAt })
    #expect(try store.recentTypes(forFlight: "LH400", userID: nil, excluding: newest.id).map(\.icaoCode) == ["A388", "B744"])
}
