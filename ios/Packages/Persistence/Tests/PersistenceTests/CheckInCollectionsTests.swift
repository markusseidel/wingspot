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

private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: 1_700_000_000 + Double(n) * 86_400) }

/// Sightings, an airport visit, a flight (with the visits it creates) and a refused check-in.
@MainActor private func fixture(_ context: ModelContext) throws -> [LocalCheckIn] {
    let store = CheckInStore(context: context)
    _ = try store.saveSpotted(SpottedDraft(registration: Registration("DAIMA"), type: a388, place: fra), at: day(1))
    _ = try store.saveSpotted(SpottedDraft(registration: Registration("DAIMA"), type: a388, place: fra), at: day(3))
    _ = try store.saveSpotted(SpottedDraft(registration: Registration("DAIMB"), type: b744, place: dus), at: day(2))
    _ = try store.saveAirport(AirportDraft(airportID: 7, code: "DUS"), at: day(4))
    _ = try store.saveFlown(FlownDraft(origin: fra, destination: jfk, registration: Registration("DAIMB"), type: b744), at: day(5))
    let refused = try store.saveSpotted(SpottedDraft(registration: Registration("DAIMA"), type: a388, place: fra), at: day(6))
    try context.fetch(FetchDescriptor<LocalCheckIn>()).first { $0.id == refused.id }?.syncState = SyncState.rejected.rawValue
    try context.save()
    return try context.fetch(FetchDescriptor<LocalCheckIn>())
}

@MainActor @Test func theListOfAnEntryAlwaysMatchesItsCount() throws {
    let all = try fixture(try makeContext())
    let lists = CheckInCollections(all, userID: nil)
    #expect(!lists.aircraft.isEmpty && !lists.types.isEmpty && !lists.airports.isEmpty)
    for entry in lists.aircraft { #expect(CheckInCollections.checkIns(of: .aircraft, key: entry.id, in: all, userID: nil).count == entry.count) }
    for entry in lists.types { #expect(CheckInCollections.checkIns(of: .type, key: entry.id, in: all, userID: nil).count == entry.count) }
    for entry in lists.airports { #expect(CheckInCollections.checkIns(of: .airport, key: entry.id, in: all, userID: nil).count == entry.count) }
}

@MainActor @Test func anAirportListHasTheVisitsAFlightCreatedAndNoRefusedCheckIns() throws {
    let all = try fixture(try makeContext())
    let fraList = CheckInCollections.checkIns(of: .airport, key: "FRA", in: all, userID: nil)
    // Two sightings and the departure visit of the flight; the refused sighting does not count, and the flight itself has no airport.
    #expect(fraList.count == 3)
    #expect(fraList.filter { $0.kind == "flown" }.isEmpty)
    #expect(fraList.contains { $0.kind == "airport" && $0.flightID != nil })
    #expect(CheckInCollections.checkIns(of: .aircraft, key: "D-AIMA", in: all, userID: nil).count == 2)
    // The flight has the registration too, so it is in the list of the aircraft
    #expect(CheckInCollections.checkIns(of: .aircraft, key: "D-AIMB", in: all, userID: nil).contains { $0.kind == "flown" })
}

@MainActor @Test func theFlightsTabListsFlightsOnly() throws {
    let all = try fixture(try makeContext())
    let flights = CheckInCollections.flights(in: all, userID: nil)
    #expect(flights.count == 1)
    #expect(flights.first?.originCode == "FRA")
}

@MainActor @Test func theListsFollowTheChosenDateAndDirection() throws {
    let context = try makeContext()
    let all = try fixture(context)
    // Entered in the opposite order of the dates of the sightings
    let sightings = CheckInCollections.checkIns(of: .aircraft, key: "D-AIMA", in: all, userID: nil)
    let early = try #require(sightings.first { $0.occurredAt == day(1) })
    let late = try #require(sightings.first { $0.occurredAt == day(3) })
    early.savedAt = day(30)
    late.savedAt = day(20)
    #expect(CheckInCollections.ordered(sightings, by: .flight, ascending: false).map(\.id) == [late.id, early.id])
    #expect(CheckInCollections.ordered(sightings, by: .flight, ascending: true).map(\.id) == [early.id, late.id])
    #expect(CheckInCollections.ordered(sightings, by: .checkIn, ascending: false).map(\.id) == [early.id, late.id])
    #expect(CheckInCollections.ordered(sightings, by: .checkIn, ascending: true).map(\.id) == [late.id, early.id])
}

@MainActor @Test func theCheckInDateFallsBackToTheUploadAndThenTheFlightDate() throws {
    let context = try makeContext()
    _ = try CheckInStore(context: context).saveSpotted(SpottedDraft(registration: Registration("DAIMA"), type: a388, place: fra), at: day(1))
    let checkIn = try #require(try context.fetch(FetchDescriptor<LocalCheckIn>()).first)
    // A new check-in has the time it was saved
    #expect(checkIn.savedAt != nil)
    #expect(checkIn.enteredAt == checkIn.savedAt)
    // Older ones, or ones restored from the server, have none
    checkIn.savedAt = nil
    #expect(checkIn.enteredAt == checkIn.occurredAt)
    checkIn.syncedAt = day(9)
    #expect(checkIn.enteredAt == day(9))
}
