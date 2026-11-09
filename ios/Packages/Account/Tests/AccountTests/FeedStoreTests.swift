import Foundation
import Testing
@testable import Account

private actor FakeFeed: FeedBackend, ReactionBackend {
    var items: [FeedItem]
    private(set) var cursors: [FeedCursor?] = []
    var error: AccountError?

    init(items: [FeedItem]) { self.items = items }

    private(set) var salutes: [(on: Bool, checkIn: UUID)] = []
    var stored: [UUID: [CheckInComment]] = [:]
    var reactionError: AccountError?

    func fail(_ error: AccountError?) { self.error = error }
    func failReactions(_ error: AccountError?) { reactionError = error }

    func setSalute(_ on: Bool, checkIn: UUID, as me: UUID) throws {
        if let reactionError { throw reactionError }
        salutes.append((on, checkIn))
    }

    func comments(checkIn: UUID) throws -> [CheckInComment] {
        if let reactionError { throw reactionError }
        return stored[checkIn] ?? []
    }

    func addComment(_ body: String, checkIn: UUID, as me: UUID) throws -> CheckInComment {
        if let reactionError { throw reactionError }
        let comment = CheckInComment(id: UUID(), userID: me, username: "me", body: body, createdAt: Date())
        stored[checkIn, default: []].append(comment)
        return comment
    }

    func deleteComment(_ id: UUID) throws {
        if let reactionError { throw reactionError }
        for key in stored.keys { stored[key]?.removeAll { $0.id == id } }
    }

    private(set) var reports: [(kind: ReportKind, target: UUID, reason: String)] = []
    var reportOutcome = ReportOutcome.reported

    func setReportOutcome(_ outcome: ReportOutcome) { reportOutcome = outcome }

    func report(_ kind: ReportKind, target: UUID, reason: String) throws -> ReportOutcome {
        if let reactionError { throw reactionError }
        reports.append((kind, target, reason))
        return reportOutcome
    }

    var photoRows: [FeedPhoto] = []
    private(set) var photoRequests: [[UUID]] = []
    var photoError: AccountError?
    func setPhotos(_ rows: [FeedPhoto]) { photoRows = rows }
    func failPhotos(_ error: AccountError?) { photoError = error }

    func photos(for checkIns: [UUID]) throws -> [FeedPhoto] {
        photoRequests.append(checkIns)
        if let photoError { throw photoError }
        return photoRows.filter { checkIns.contains($0.checkInID) }
    }

    private(set) var personRequests: [UUID] = []
    func personCheckIns(of person: UUID, after cursor: FeedCursor?, pageSize: Int) throws -> [FeedItem] {
        personRequests.append(person)
        if let error { throw error }
        return items.filter { $0.userID == person }
    }

    private(set) var airportRequests: [Int] = []
    var activity = AirportActivity(checkIns: 0, aircraft: 0)
    func airportCheckIns(at airport: Int, after cursor: FeedCursor?, pageSize: Int) throws -> [FeedItem] {
        airportRequests.append(airport)
        if let error { throw error }
        return items.filter { $0.airportID == airport }
    }
    func airportActivity(at airport: Int) throws -> AirportActivity { activity }
    private(set) var typeRequests: [String] = []
    var typeCounts = TypeActivity(checkIns: 0, airports: 0)
    func typeCheckIns(of type: String, after cursor: FeedCursor?, pageSize: Int) throws -> [FeedItem] {
        typeRequests.append(type)
        if let error { throw error }
        return items.filter { $0.typeICAO == type }
    }
    func typeActivity(of type: String) throws -> TypeActivity { typeCounts }
    private(set) var registrationRequests: [String] = []
    func registrationCheckIns(of registration: String, after cursor: FeedCursor?, pageSize: Int) throws -> [FeedItem] {
        registrationRequests.append(registration)
        if let error { throw error }
        return items.filter { $0.registration == registration }
    }
    var busy: [ActiveAirport] = []
    func activeAirports(days: Int, limit: Int) throws -> [ActiveAirport] {
        if let error { throw error }
        return Array(busy.prefix(limit))
    }

    func replace(_ items: [FeedItem]) { self.items = items }
    func setBusy(_ rows: [ActiveAirport]) { busy = rows }

    func feed(after cursor: FeedCursor?, pageSize: Int) throws -> [FeedItem] {
        cursors.append(cursor)
        if let error { throw error }
        var rest = items
        if let cursor, let index = items.firstIndex(where: { $0.id == cursor.id }) {
            rest = Array(items[(index + 1)...])
        }
        return Array(rest.prefix(pageSize))
    }
}

private let me = UUID()

@MainActor private func makeStore(_ backend: FakeFeed) -> FeedStore {
    FeedStore(backend: backend, reactions: backend, userID: { me })
}

private func item(_ n: Int) -> FeedItem {
    FeedItem(
        id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!, userID: UUID(), username: "u\(n)",
        kind: "spotted", occurredAt: Date(timeIntervalSince1970: Double(10_000 - n)), registration: "D-A\(n)"
    )
}

@MainActor @Test func theFirstPageFillsTheList() async {
    let store = makeStore(FakeFeed(items: (1...5).map(item)))
    #expect(!store.hasLoaded)
    await store.refresh()
    #expect(store.items.count == 5)
    #expect(store.hasLoaded)
    #expect(store.reachedEnd)
}

@MainActor @Test func moreIsLoadedFromTheLastItemUntilTheEnd() async {
    let backend = FakeFeed(items: (1...70).map(item))
    let store = makeStore(backend)
    await store.refresh()
    #expect(store.items.count == 30)
    #expect(!store.reachedEnd)
    await store.loadMore()
    #expect(store.items.count == 60)
    await store.loadMore()
    #expect(store.items.count == 70)
    #expect(store.reachedEnd)
    await store.loadMore()
    #expect(await backend.cursors.count == 3, "nothing is asked for once the end is reached")
    #expect(await backend.cursors[1]?.id == item(30).id)
    #expect(Set(store.items.map(\.id)).count == 70)
}

@MainActor @Test func loadMoreDoesNothingBeforeTheFirstPage() async {
    let backend = FakeFeed(items: (1...5).map(item))
    let store = makeStore(backend)
    await store.loadMore()
    #expect(await backend.cursors.isEmpty)
}

@MainActor @Test func refreshReplacesTheList() async {
    let backend = FakeFeed(items: (1...3).map(item))
    let store = makeStore(backend)
    await store.refresh()
    await backend.replace([item(9)])
    await store.refresh()
    #expect(store.items.map(\.username) == ["u9"])
}

@MainActor @Test func aFailedRefreshKeepsWhatWasThere() async {
    let backend = FakeFeed(items: (1...3).map(item))
    let store = makeStore(backend)
    await store.refresh()
    await backend.fail(.offline)
    await store.refresh()
    #expect(store.items.count == 3)
    #expect(store.failure == .offline)
    await backend.fail(nil)
    await store.refresh()
    #expect(store.failure == nil)
}

@MainActor @Test func repeatedItemsAreDropped() async {
    let backend = FakeFeed(items: [item(1), item(1), item(2)])
    let store = makeStore(backend)
    await store.refresh()
    #expect(store.items.map(\.username) == ["u1", "u2"])
}

@MainActor @Test func clearForgetsEverything() async {
    let store = makeStore(FakeFeed(items: (1...3).map(item)))
    await store.refresh()
    store.clear()
    #expect(store.items.isEmpty)
    #expect(!store.hasLoaded)
}

@Test func theServersAnswerIsDecoded() throws {
    let json = """
    [{"id":"50000000-0000-0000-0000-000000000002","user_id":"00000000-0000-0000-0000-000000000501",
      "username":"anna_spots","display_name":null,"kind":"flown","occurred_at":"2026-11-06T22:26:14.572123+00:00",
      "registration":null,"type_icao":"A320","type_name":"Airbus A320","airport_id":null,"airport_code":null,
      "origin_code":"FRA","destination_code":"JFK","flight_number":"LH400","distance_km":6200,
      "salutes":2,"comments":1,"saluted":true},
     {"id":"50000000-0000-0000-0000-000000000003","user_id":"00000000-0000-0000-0000-000000000501",
      "username":"anna_spots","display_name":"Anna","kind":"spotted","occurred_at":"2026-11-06T22:00:00+00:00",
      "registration":"D-AIZZ","type_icao":null,"type_name":null,"airport_id":3,"airport_code":"FRA",
      "origin_code":null,"destination_code":null,"flight_number":null,"distance_km":null,
      "salutes":0,"comments":0,"saluted":false}]
    """
    let items = try JSONDecoder().decode([FeedItem].self, from: Data(json.utf8))
    #expect(items.count == 2)
    #expect(items[0].originCode == "FRA")
    #expect(items[0].distanceKm == 6200)
    #expect(items[0].salutes == 2)
    #expect(items[0].saluted)
    #expect(items[0].cursorTime == "2026-11-06T22:26:14.572123+00:00", "the time is kept exactly for paging")
    #expect(items[1].registration == "D-AIZZ")
    #expect(items[1].occurredAt < items[0].occurredAt)
}

@MainActor @Test func aSaluteChangesTheCardAtOnceAndTheServerHearsOfIt() async {
    let backend = FakeFeed(items: [item(1)])
    let store = makeStore(backend)
    await store.refresh()
    await store.toggleSalute(item(1).id)
    #expect(store.items[0].saluted)
    #expect(store.items[0].salutes == 1)
    #expect(await backend.salutes.map(\.on) == [true])
    await store.toggleSalute(item(1).id)
    #expect(!store.items[0].saluted)
    #expect(store.items[0].salutes == 0)
    #expect(await backend.salutes.map(\.on) == [true, false])
}

@MainActor @Test func aFailedSaluteGoesBack() async {
    let backend = FakeFeed(items: [item(1)])
    let store = makeStore(backend)
    await store.refresh()
    await backend.failReactions(.offline)
    await store.toggleSalute(item(1).id)
    #expect(!store.items[0].saluted)
    #expect(store.items[0].salutes == 0)
    #expect(store.failure == .offline)
}

@MainActor @Test func theCommentCountFollowsTheCommentsScreen() async {
    let store = makeStore(FakeFeed(items: [item(1)]))
    await store.refresh()
    store.setCommentCount(4, for: item(1).id)
    #expect(store.items[0].comments == 4)
    store.setCommentCount(2, for: UUID())
    #expect(store.items[0].comments == 4)
}

@MainActor @Test func commentsLoadSendAndDelete() async throws {
    let backend = FakeFeed(items: [item(1)])
    var counts: [Int] = []
    let box = CountBox()
    let comments = CheckInCommentStore(checkIn: item(1).id, backend: backend, userID: { me }, onCountChange: { box.counts.append($0) })
    await comments.load()
    #expect(comments.hasLoaded)
    #expect(comments.comments.isEmpty)
    try await comments.send("  Great shot!  ")
    #expect(comments.comments.map(\.body) == ["Great shot!"])
    await comments.delete(comments.comments[0])
    #expect(comments.comments.isEmpty)
    counts = box.counts
    #expect(counts == [0, 1, 0])
}

@MainActor private final class CountBox { var counts: [Int] = [] }

@MainActor @Test func emptyOrTooLongCommentsAreNotSent() async {
    #expect(!CheckInCommentStore.isSendable("   "))
    #expect(CheckInCommentStore.isSendable("ok"))
    #expect(!CheckInCommentStore.isSendable(String(repeating: "a", count: CheckInCommentStore.maxLength + 1)))
    let comments = CheckInCommentStore(checkIn: UUID(), backend: FakeFeed(items: []), userID: { me })
    await #expect(throws: AccountError.unknown) { try await comments.send("  ") }
}

@MainActor @Test func aRefusedCommentReachesTheCaller() async {
    let backend = FakeFeed(items: [])
    await backend.failReactions(.contentNotAllowed)
    let comments = CheckInCommentStore(checkIn: UUID(), backend: backend, userID: { me })
    await #expect(throws: AccountError.contentNotAllowed) { try await comments.send("rude") }
    #expect(comments.comments.isEmpty)
}

@Test func aCommentWithItsEmbeddedAuthorIsDecoded() throws {
    let json = """
    [{"id":"60000000-0000-0000-0000-000000000001","user_id":"00000000-0000-0000-0000-000000000501",
      "body":"Nice one","created_at":"2026-11-07T09:00:00.5+00:00",
      "profiles":{"username":"anna_spots","display_name":"Anna"}}]
    """
    let comments = try JSONDecoder().decode([CheckInComment].self, from: Data(json.utf8))
    #expect(comments[0].username == "anna_spots")
    #expect(comments[0].displayName == "Anna")
    #expect(comments[0].body == "Nice one")
}

@Test @MainActor func reportSendsReasonAndDetails() async throws {
    let backend = FakeFeed(items: [])
    let target = UUID()
    try await Reporter(backend: backend).report(.comment, target: target, reason: .offensive, details: "  rude  ")
    try await Reporter(backend: backend).report(.user, target: target, reason: .spam, details: "")
    let sent = await backend.reports
    #expect(sent.map(\.reason) == ["offensive: rude", "spam"])
    #expect(sent.map(\.kind) == [.comment, .user])
}

@Test @MainActor func reportRefusalsBecomeErrors() async {
    let backend = FakeFeed(items: [])
    let reporter = Reporter(backend: backend)
    await backend.setReportOutcome(.tooMany)
    await #expect(throws: AccountError.tooManyRequests) {
        try await reporter.report(.user, target: UUID(), reason: .other, details: "")
    }
    await backend.setReportOutcome(.unknownTarget)
    await #expect(throws: AccountError.unknown) {
        try await reporter.report(.user, target: UUID(), reason: .other, details: "")
    }
}

@Test @MainActor func termsAreAcceptedPerAccount() throws {
    let defaults = try #require(UserDefaults(suiteName: "TermsTests-\(UUID().uuidString)"))
    var current: UUID? = nil
    let terms = TermsStore(defaults: defaults, userID: { current })
    #expect(!terms.hasAccepted)
    let first = UUID()
    current = first
    #expect(!terms.hasAccepted)
    terms.accept()
    #expect(terms.hasAccepted)
    current = UUID()
    #expect(!terms.hasAccepted)
    current = first
    #expect(TermsStore(defaults: defaults, userID: { first }).hasAccepted)
}

@Test @MainActor func photosArriveWithTheirCheckIns() async throws {
    let backend = FakeFeed(items: (1...3).map(item))
    let first = item(1).id
    let url = try #require(URL(string: "https://example.test/a.jpg"))
    await backend.setPhotos([FeedPhoto(id: UUID(), checkInID: first, url: url)])
    let store = makeStore(backend)
    await store.refresh()
    #expect(store.photos[first]?.count == 1)
    #expect(store.photos[item(2).id] == nil)
    store.clear()
    #expect(store.photos.isEmpty)
}

@Test @MainActor func aPhotoFailureDoesNotHideTheFeed() async {
    let backend = FakeFeed(items: (1...3).map(item))
    await backend.failPhotos(.offline)
    let store = makeStore(backend)
    await store.refresh()
    #expect(store.items.count == 3)
    #expect(store.failure == nil)
    #expect(store.photos.isEmpty)
}

@Test @MainActor func aPersonsPageAsksForThatPerson() async {
    let other = UUID()
    let backend = FakeFeed(items: (1...3).map(item))
    let store = FeedStore(backend: backend, reactions: backend, person: other, userID: { me })
    await store.refresh()
    #expect(await backend.personRequests == [other])
    #expect(await backend.cursors.isEmpty, "the feed itself was not asked")
    #expect(store.hasLoaded)
}

@Test @MainActor func anAirportPageAsksForThatAirport() async {
    let backend = FakeFeed(items: (1...3).map(item))
    let store = makeStore(backend).airportStore(for: 42)
    await store.refresh()
    #expect(await backend.airportRequests == [42])
    #expect(await backend.cursors.isEmpty, "the feed itself was not asked")
    #expect(await backend.personRequests.isEmpty)
    #expect(store.hasLoaded)
}

@Test func airportCountsAreDecoded() throws {
    let json = """
    [{"checkins_30d":5,"aircraft_30d":3,"top_spotters":[
      {"user_id":"00000000-0000-0000-0000-000000000001","username":"anna","display_name":null,"checkins":4}]}]
    """
    let rows = try JSONDecoder().decode([AirportActivity].self, from: Data(json.utf8))
    #expect(rows.first?.checkIns == 5)
    #expect(rows.first?.aircraft == 3)
    #expect(rows.first?.topSpotters.first?.username == "anna")
    #expect(rows.first?.topSpotters.first?.checkIns == 4)
}

@Test func aFeedRowKeepsItsAirportID() throws {
    let json = """
    [{"id":"00000000-0000-0000-0000-000000000001","user_id":"00000000-0000-0000-0000-000000000002","username":"anna",
      "display_name":null,"kind":"airport","occurred_at":"2026-11-07T10:00:00+00:00","registration":null,"type_icao":null,
      "type_name":null,"airport_id":3,"airport_code":"FRA","origin_code":null,"destination_code":null,"flight_number":null,
      "distance_km":null,"salutes":0,"comments":0,"saluted":false}]
    """
    let rows = try JSONDecoder().decode([FeedItem].self, from: Data(json.utf8))
    #expect(rows.first?.airportID == 3)
}

@Test func busyAirportsAreDecoded() throws {
    let json = """
    [{"airport_id":3,"airport_code":"FRA","airport_name":"Frankfurt am Main Airport","city":"Frankfurt","checkins":12,"people":4},
     {"airport_id":9,"airport_code":"XYZ","airport_name":"Small Field","city":null,"checkins":1,"people":1}]
    """
    let rows = try JSONDecoder().decode([ActiveAirport].self, from: Data(json.utf8))
    #expect(rows.map(\.code) == ["FRA", "XYZ"])
    #expect(rows[0].checkIns == 12)
    #expect(rows[0].people == 4)
    #expect(rows[1].city == nil)
}

@Test @MainActor func busyAirportsComeFromTheBackendAndKeepTheirOrder() async throws {
    let backend = FakeFeed(items: [])
    await backend.setBusy([
        ActiveAirport(airportID: 1, code: "FRA", name: "Frankfurt", checkIns: 5, people: 2),
        ActiveAirport(airportID: 2, code: "VIE", name: "Vienna", checkIns: 3, people: 1),
    ])
    let store = makeStore(backend)
    #expect(try await store.activeAirports(days: 7, limit: 10).map(\.code) == ["FRA", "VIE"])
    #expect(try await store.activeAirports(days: 7, limit: 1).count == 1)
    await backend.fail(.offline)
    await #expect(throws: AccountError.self) { try await store.activeAirports() }
}

@Test @MainActor func aTypePageAsksForThatType() async {
    let backend = FakeFeed(items: (1...3).map(item))
    let store = makeStore(backend).typeStore(for: "A320")
    await store.refresh()
    #expect(await backend.typeRequests == ["A320"])
    #expect(await backend.cursors.isEmpty, "the feed itself was not asked")
    #expect(await backend.airportRequests.isEmpty)
    #expect(store.hasLoaded)
}

@Test func typeCountsAreDecoded() throws {
    let json = """
    [{"checkins_30d":7,"airports_30d":2,"top_spotters":[
      {"user_id":"00000000-0000-0000-0000-000000000001","username":"anna","display_name":null,"checkins":4}]}]
    """
    let rows = try JSONDecoder().decode([TypeActivity].self, from: Data(json.utf8))
    #expect(rows.first?.checkIns == 7)
    #expect(rows.first?.airports == 2)
    #expect(rows.first?.topSpotters.first?.username == "anna")
}

@Test @MainActor func anAircraftPageAsksForThatRegistration() async {
    let backend = FakeFeed(items: (1...3).map(item))
    let store = makeStore(backend).registrationStore(for: "D-AIXY")
    await store.refresh()
    #expect(await backend.registrationRequests == ["D-AIXY"])
    #expect(await backend.cursors.isEmpty, "the feed itself was not asked")
    #expect(await backend.typeRequests.isEmpty)
    #expect(store.hasLoaded)
}
