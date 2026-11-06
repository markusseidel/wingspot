import Foundation
import Persistence
import SwiftData
import Testing
import WingspotCore

@MainActor
private func makeContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: LocalCheckIn.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return ModelContext(container)
}

private let a388 = SpottedDraft.AircraftTypeChoice(icaoCode: "A388", name: "Airbus A380-800")
private let fra = SpottedDraft.Place(airportID: 3, code: "FRA")
private let dus = SpottedDraft.Place(airportID: 7, code: "DUS")

@MainActor @Test func theFirstSightingIsReportedAsFirst() throws {
    let store = CheckInStore(context: try makeContext())
    let result = try store.saveSpotted(SpottedDraft(registration: Registration("DAIMA")))
    #expect(result.subject == "D-AIMA")
    #expect(result.history == .firstTime)
}

@MainActor @Test func repeatSightingsCountAndNameTheLastPlace() throws {
    let store = CheckInStore(context: try makeContext())
    let first = Date(timeIntervalSince1970: 1_000)
    let second = Date(timeIntervalSince1970: 2_000)
    _ = try store.saveSpotted(SpottedDraft(registration: Registration("DAIMA"), place: fra), at: first)
    _ = try store.saveSpotted(SpottedDraft(registration: Registration("DAIMA"), place: dus), at: second)
    let result = try store.saveSpotted(SpottedDraft(registration: Registration("DAIMA")), at: Date(timeIntervalSince1970: 3_000))
    #expect(result.history == .seenBefore(count: 3, lastSeen: second, lastPlace: "DUS"))
}

@MainActor @Test func aDifferentRegistrationIsANewSighting() throws {
    let store = CheckInStore(context: try makeContext())
    _ = try store.saveSpotted(SpottedDraft(registration: Registration("DAIMA")))
    let result = try store.saveSpotted(SpottedDraft(registration: Registration("DAIMB")))
    #expect(result.history == .firstTime)
}

@MainActor @Test func aTypeOnlyCheckInCountsThatType() throws {
    let store = CheckInStore(context: try makeContext())
    _ = try store.saveSpotted(SpottedDraft(registration: Registration("DAIMA"), type: a388))
    let result = try store.saveSpotted(SpottedDraft(type: a388))
    #expect(result.subject == "A388")
    if case .seenBefore(let count, _, _) = result.history { #expect(count == 2) } else { Issue.record("expected a count") }
}

@MainActor @Test func aCheckInWithoutAircraftIsRejected() throws {
    let context = try makeContext()
    #expect(throws: CheckInError.missingAircraft) {
        try CheckInStore(context: context).saveSpotted(SpottedDraft(place: fra))
    }
    #expect(try context.fetchCount(FetchDescriptor<LocalCheckIn>()) == 0)
}

@MainActor @Test func aSavedCheckInWaitsForSync() throws {
    let context = try makeContext()
    let position = GeoCoordinate(latitude: 50.03, longitude: 8.57)
    let result = try CheckInStore(context: context).saveSpotted(
        SpottedDraft(registration: Registration("DAIMA"), type: a388, place: fra, position: position)
    )
    let saved = try #require(try context.fetch(FetchDescriptor<LocalCheckIn>()).first)
    #expect(saved.id == result.id)
    #expect(saved.syncState == "pending")
    #expect(saved.kind == "spotted")
    #expect(saved.registration == "D-AIMA")
    #expect(saved.typeICAO == "A388")
    #expect(saved.airportID == 3)
    #expect(saved.latitude == 50.03)
}

@MainActor @Test func checkInsSurviveReopeningTheStore() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).store")
    func open() throws -> ModelContext {
        ModelContext(try ModelContainer(for: LocalCheckIn.self, configurations: ModelConfiguration(url: url)))
    }
    _ = try CheckInStore(context: open()).saveSpotted(SpottedDraft(registration: Registration("DAIMA")))
    let result = try CheckInStore(context: open()).saveSpotted(SpottedDraft(registration: Registration("DAIMA")))
    if case .seenBefore(let count, _, _) = result.history { #expect(count == 2) } else { Issue.record("expected a count") }
}

@MainActor @Test func theFirstVisitToAnAirportIsReportedAsFirst() throws {
    let context = try makeContext()
    let result = try CheckInStore(context: context).saveAirport(AirportDraft(airportID: 3, code: "FRA", context: .arriving))
    #expect(result.code == "FRA")
    #expect(result.history == .firstTime)
    let saved = try #require(try context.fetch(FetchDescriptor<LocalCheckIn>()).first)
    #expect(saved.kind == "airport")
    #expect(saved.visitContext == "arriving")
    #expect(saved.syncState == "pending")
    #expect(saved.registration == nil)
}

@MainActor @Test func visitsCountEarlierCheckInsOfAnyKindAtThatAirport() throws {
    let store = CheckInStore(context: try makeContext())
    _ = try store.saveSpotted(SpottedDraft(registration: Registration("DAIMA"), place: fra), at: Date(timeIntervalSince1970: 1_000))
    _ = try store.saveAirport(AirportDraft(airportID: 3, code: "FRA"), at: Date(timeIntervalSince1970: 2_000))
    _ = try store.saveAirport(AirportDraft(airportID: 7, code: "DUS"), at: Date(timeIntervalSince1970: 2_500))
    let result = try store.saveAirport(AirportDraft(airportID: 3, code: "FRA"), at: Date(timeIntervalSince1970: 3_000))
    #expect(result.history == .visitedBefore(count: 3, lastVisit: Date(timeIntervalSince1970: 2_000)))
}
