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
    #expect(stats.checkIns == 5)
    #expect(stats.sightings == 3)
    #expect(stats.airportVisits == 1)
    #expect(stats.flights == 1)
    #expect(stats.aircraft == 2)
    #expect(stats.types == 2)
    // FRA and DUS. The flight's JFK doesn't count.
    #expect(stats.airports == 2)
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
