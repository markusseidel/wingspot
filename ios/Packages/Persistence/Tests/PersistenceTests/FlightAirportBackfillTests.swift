import Foundation
import Persistence
import SwiftData
import Testing

@MainActor
private func makeContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: LocalCheckIn.self, LocalPhoto.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return ModelContext(container)
}

private let fra = SpottedDraft.Place(airportID: 3, code: "FRA")
private let jfk = SpottedDraft.Place(airportID: 9, code: "JFK")

/// A flight saved the way build 14 did, without airport check-ins.
@MainActor
private func saveOldStyleFlight(_ context: ModelContext, at date: Date) throws {
    _ = try CheckInStore(context: context).saveFlown(FlownDraft(origin: fra, destination: jfk), at: date)
    for checkIn in try context.fetch(FetchDescriptor<LocalCheckIn>()) where checkIn.kind == "airport" {
        context.delete(checkIn)
    }
    try context.save()
}

@MainActor @Test func earlierFlightsGetTheirTwoAirports() throws {
    let context = try makeContext()
    try saveOldStyleFlight(context, at: Date(timeIntervalSince1970: 1_700_000_000))

    #expect(try FlightAirportBackfill(context: context).run() == 2)
    let airports = try context.fetch(FetchDescriptor<LocalCheckIn>()).filter { $0.kind == "airport" }
    #expect(Set(airports.compactMap(\.airportCode)) == ["FRA", "JFK"])
    #expect(Set(airports.compactMap(\.visitContext)) == ["departing", "arriving"])
    #expect(airports.allSatisfy { $0.syncState == "pending" })
}

@MainActor @Test func runningItAgainAddsNothing() throws {
    let context = try makeContext()
    try saveOldStyleFlight(context, at: Date(timeIntervalSince1970: 1_700_000_000))
    try FlightAirportBackfill(context: context).run()
    #expect(try FlightAirportBackfill(context: context).run() == 0)
}

@MainActor @Test func flightsThatAlreadyCheckedInTheirAirportsAreLeftAlone() throws {
    let context = try makeContext()
    _ = try CheckInStore(context: context).saveFlown(FlownDraft(origin: fra, destination: jfk), at: Date(timeIntervalSince1970: 1_700_000_000))
    #expect(try FlightAirportBackfill(context: context).run() == 0)
}

@MainActor @Test func anAirportVisitOnTheSameDayCountsAsCovered() throws {
    let context = try makeContext()
    let day = Date(timeIntervalSince1970: 1_700_000_000)
    try saveOldStyleFlight(context, at: day)
    _ = try CheckInStore(context: context).saveAirport(AirportDraft(airportID: 3, code: "FRA"), at: day)

    #expect(try FlightAirportBackfill(context: context).run() == 1)
}
