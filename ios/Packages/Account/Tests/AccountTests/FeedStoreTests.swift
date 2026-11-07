import Foundation
import Testing
@testable import Account

private actor FakeFeed: FeedBackend {
    var items: [FeedItem]
    private(set) var cursors: [FeedCursor?] = []
    var error: AccountError?

    init(items: [FeedItem]) { self.items = items }

    func fail(_ error: AccountError?) { self.error = error }
    func replace(_ items: [FeedItem]) { self.items = items }

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

private func item(_ n: Int) -> FeedItem {
    FeedItem(
        id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!, userID: UUID(), username: "u\(n)",
        kind: "spotted", occurredAt: Date(timeIntervalSince1970: Double(10_000 - n)), registration: "D-A\(n)"
    )
}

@MainActor @Test func theFirstPageFillsTheList() async {
    let store = FeedStore(backend: FakeFeed(items: (1...5).map(item)))
    #expect(!store.hasLoaded)
    await store.refresh()
    #expect(store.items.count == 5)
    #expect(store.hasLoaded)
    #expect(store.reachedEnd)
}

@MainActor @Test func moreIsLoadedFromTheLastItemUntilTheEnd() async {
    let backend = FakeFeed(items: (1...70).map(item))
    let store = FeedStore(backend: backend)
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
    let store = FeedStore(backend: backend)
    await store.loadMore()
    #expect(await backend.cursors.isEmpty)
}

@MainActor @Test func refreshReplacesTheList() async {
    let backend = FakeFeed(items: (1...3).map(item))
    let store = FeedStore(backend: backend)
    await store.refresh()
    await backend.replace([item(9)])
    await store.refresh()
    #expect(store.items.map(\.username) == ["u9"])
}

@MainActor @Test func aFailedRefreshKeepsWhatWasThere() async {
    let backend = FakeFeed(items: (1...3).map(item))
    let store = FeedStore(backend: backend)
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
    let store = FeedStore(backend: backend)
    await store.refresh()
    #expect(store.items.map(\.username) == ["u1", "u2"])
}

@MainActor @Test func clearForgetsEverything() async {
    let store = FeedStore(backend: FakeFeed(items: (1...3).map(item)))
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
