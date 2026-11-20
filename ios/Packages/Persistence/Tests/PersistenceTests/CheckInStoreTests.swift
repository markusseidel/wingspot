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

@MainActor @Test func aFlightIsSavedWithItsRouteAndCountsRepeats() throws {
    let context = try makeContext()
    let store = CheckInStore(context: context)
    let draft = FlownDraft(
        origin: fra, destination: dus, distanceKm: 180, flightNumber: "lh 400", registration: Registration("DAIMA"),
        cabin: .premiumEconomy, seat: "34k"
    )
    let first = try store.saveFlown(draft, at: Date(timeIntervalSince1970: 1_000))
    #expect(first.route == "FRA → DUS")
    #expect(first.timesOnRoute == 1)
    let second = try store.saveFlown(draft, at: Date(timeIntervalSince1970: 2_000))
    #expect(second.timesOnRoute == 2)
    let reverse = try store.saveFlown(FlownDraft(origin: dus, destination: fra), at: Date(timeIntervalSince1970: 3_000))
    #expect(reverse.timesOnRoute == 1)

    let saved = try #require(try context.fetch(FetchDescriptor<LocalCheckIn>()).first { $0.id == first.id })
    #expect(saved.kind == "flown")
    #expect(saved.flightNumber == "LH400")
    #expect(saved.seat == "34K")
    #expect(saved.cabin == "premium_economy")
    #expect(saved.registration == "D-AIMA")
    #expect(saved.syncState == "pending")
}

@MainActor @Test func aFlightNeedsTwoDifferentAirports() throws {
    let context = try makeContext()
    #expect(throws: CheckInError.sameAirport) {
        try CheckInStore(context: context).saveFlown(FlownDraft(origin: fra, destination: fra))
    }
    #expect(try context.fetchCount(FetchDescriptor<LocalCheckIn>()) == 0)
}

@MainActor @Test func aFlightCanGetItsAircraftLaterAndIsSentAgain() throws {
    let context = try makeContext()
    let store = CheckInStore(context: context)
    let result = try store.saveFlown(FlownDraft(origin: SpottedDraft.Place(airportID: 3, code: "FRA"), destination: SpottedDraft.Place(airportID: 9, code: "JFK")))
    let flight = try #require(try context.fetch(FetchDescriptor<LocalCheckIn>()).first { $0.id == result.id })
    flight.syncState = SyncState.synced.rawValue

    let type = SpottedDraft.AircraftTypeChoice(icaoCode: "A388", name: "Airbus A380-800")
    #expect(try store.updateFlown(id: result.id, registration: Registration("DAIMA"), type: type, flightNumber: "lh 400", cabin: .economy, seat: " 12a "))

    #expect(flight.registration == "D-AIMA")
    #expect(flight.typeICAO == "A388")
    #expect(flight.typeName == "Airbus A380-800")
    #expect(flight.flightNumber == "LH400")
    #expect(flight.cabin == CabinClass.economy.rawValue)
    #expect(flight.seat == "12A")
    #expect(flight.syncState == SyncState.pending.rawValue)
    #expect(flight.originCode == "FRA")
}

@MainActor @Test func editingAFlightThisDeviceDoesNotHaveChangesNothing() throws {
    let context = try makeContext()
    #expect(try CheckInStore(context: context).updateFlown(id: UUID(), registration: nil, type: nil, flightNumber: nil, cabin: nil, seat: nil) == false)
}

@MainActor @Test func deletingACheckInRemovesItAndItsPhotoFromThisDevice() throws {
    let context = try makeContext()
    let store = CheckInStore(context: context)
    let kept = try store.saveSpotted(SpottedDraft(registration: Registration("DAIMA")))
    let gone = try store.saveSpotted(SpottedDraft(registration: Registration("DAIMB")))

    try store.deleteLocal(id: gone.id)
    try store.deleteLocal(id: UUID())

    let left = try context.fetch(FetchDescriptor<LocalCheckIn>())
    #expect(left.map(\.id) == [kept.id])
}

@MainActor @Test func deletingAFlightRemovesItsTwoAirportVisitsAndNothingElse() throws {
    let context = try makeContext()
    let store = CheckInStore(context: context)
    let day = Date(timeIntervalSince1970: 1_000_000)
    let spotting = try store.saveAirport(AirportDraft(airportID: 7, code: "DUS", context: .spotting), at: day)
    let otherDay = try store.saveAirport(AirportDraft(airportID: 3, code: "FRA", context: .departing), at: Date(timeIntervalSince1970: 2_000_000))
    let flight = try store.saveFlown(FlownDraft(origin: fra, destination: dus), at: day)

    let removed = try store.deleteLocal(id: flight.id)

    let left = try context.fetch(FetchDescriptor<LocalCheckIn>()).map(\.id)
    #expect(Set(left) == Set([spotting.id, otherDay.id]))
    #expect(removed.count == 3 && removed.contains(flight.id))
}

@MainActor @Test func twoFlightsAtTheSameTimeEachTakeOnlyTheirOwnLinkedVisits() throws {
    let context = try makeContext()
    let store = CheckInStore(context: context)
    let day = Date(timeIntervalSince1970: 1_000_000)
    let first = try store.saveFlown(FlownDraft(origin: fra, destination: dus), at: day)
    let second = try store.saveFlown(FlownDraft(origin: fra, destination: dus), at: day)

    try store.deleteLocal(id: first.id)
    let left = try context.fetch(FetchDescriptor<LocalCheckIn>())
    #expect(left.count == 3 && left.filter { $0.flightID == second.id }.count == 2)
    try store.deleteLocal(id: second.id)
    #expect(try context.fetch(FetchDescriptor<LocalCheckIn>()).isEmpty)
}

@MainActor @Test func visitsWithoutALinkAreFoundByTimeAndAirportsUnlessAnotherFlightUsesThem() throws {
    let context = try makeContext()
    let store = CheckInStore(context: context)
    let day = Date(timeIntervalSince1970: 1_000_000)
    let first = try store.saveFlown(FlownDraft(origin: fra, destination: dus), at: day)
    let second = try store.saveFlown(FlownDraft(origin: fra, destination: dus), at: day)
    // As saved by an older version, which didn't link them.
    for checkIn in try context.fetch(FetchDescriptor<LocalCheckIn>()) { checkIn.flightID = nil }

    try store.deleteLocal(id: first.id)
    #expect(try context.fetch(FetchDescriptor<LocalCheckIn>()).count == 5)
    try store.deleteLocal(id: second.id)
    #expect(try context.fetch(FetchDescriptor<LocalCheckIn>()).isEmpty)
}

@MainActor @Test func aLinkedVisitMovesWithItsFlightWhateverItsTimeIs() throws {
    let context = try makeContext()
    let store = CheckInStore(context: context)
    let day = Date(timeIntervalSince1970: 1_000_000)
    let flight = try store.saveFlown(FlownDraft(origin: fra, destination: dus), at: day)
    let visit = try #require(try context.fetch(FetchDescriptor<LocalCheckIn>()).first { $0.kind == "airport" })
    visit.occurredAt = day.addingTimeInterval(60)
    let newDay = Date(timeIntervalSince1970: 500_000)

    #expect(try store.updateFlown(id: flight.id, registration: nil, type: nil, flightNumber: nil, cabin: nil, seat: nil, occurredAt: newDay))
    let visits = try context.fetch(FetchDescriptor<LocalCheckIn>()).filter { $0.kind == "airport" }
    #expect(visits.count == 2 && visits.allSatisfy { $0.occurredAt == newDay })
}

@MainActor @Test func changingTheDayOfAFlightMovesItsAirportVisitsToo() throws {
    let context = try makeContext()
    let store = CheckInStore(context: context)
    let day = Date(timeIntervalSince1970: 1_000_000)
    let spotting = try store.saveAirport(AirportDraft(airportID: 7, code: "DUS", context: .spotting), at: day)
    let flight = try store.saveFlown(FlownDraft(origin: fra, destination: dus), at: day)
    let newDay = Date(timeIntervalSince1970: 500_000)

    #expect(try store.updateFlown(
        id: flight.id, registration: nil, type: nil, flightNumber: nil, cabin: nil, seat: nil, occurredAt: newDay
    ))

    let all = try context.fetch(FetchDescriptor<LocalCheckIn>())
    #expect(all.first { $0.id == flight.id }?.occurredAt == newDay)
    let visits = all.filter { $0.kind == "airport" && ($0.visitContext == "departing" || $0.visitContext == "arriving") }
    #expect(visits.count == 2)
    #expect(visits.allSatisfy { $0.occurredAt == newDay })
    #expect(all.first { $0.id == spotting.id }?.occurredAt == day, "a spotting visit keeps its time")
}

@Test func aFlightKeepsTheRealTimeOnlyForToday() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(FlightDay.moment(of: now.addingTimeInterval(-60), now: now) == now)
    let other = FlightDay.moment(of: now.addingTimeInterval(-3 * 86_400), now: now)
    #expect(Calendar.current.component(.hour, from: other) == 12)
}

@MainActor @Test func aSightingsAircraftIsCorrectedAndSentAgain() throws {
    let context = try makeContext()
    let store = CheckInStore(context: context)
    let result = try store.saveSpotted(SpottedDraft(registration: Registration("DAIMA")))
    #expect(try store.updateSpotted(id: result.id, registration: Registration("DAIMB"), type: a388))
    let saved = try #require(try context.fetch(FetchDescriptor<LocalCheckIn>()).first { $0.id == result.id })
    #expect(saved.registration == "D-AIMB")
    #expect(saved.typeICAO == "A388")
    #expect(saved.syncState == SyncState.pending.rawValue)
}

@MainActor @Test func aSightingNeedsARegistrationOrATypeAndMustExist() throws {
    let store = CheckInStore(context: try makeContext())
    let result = try store.saveSpotted(SpottedDraft(registration: Registration("DAIMA")))
    #expect(try store.updateSpotted(id: result.id, registration: nil, type: nil) == false)
    #expect(try store.updateSpotted(id: UUID(), registration: Registration("DAIMB"), type: nil) == false)
}

@MainActor @Test func theReasonForAVisitIsCorrectedAndSentAgain() throws {
    let context = try makeContext()
    let store = CheckInStore(context: context)
    let result = try store.saveAirport(AirportDraft(airportID: 3, code: "FRA", context: .spotting))
    #expect(try store.updateVisit(id: result.id, reason: .museum))
    let saved = try #require(try context.fetch(FetchDescriptor<LocalCheckIn>()).first { $0.id == result.id })
    #expect(saved.visitContext == "museum")
    #expect(saved.syncState == SyncState.pending.rawValue)
    #expect(try store.updateVisit(id: UUID(), reason: .working) == false)
}
