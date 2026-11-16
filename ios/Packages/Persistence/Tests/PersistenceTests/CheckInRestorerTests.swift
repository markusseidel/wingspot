import Foundation
@testable import Persistence
import SwiftData
import Testing

@MainActor
private func makeContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: LocalCheckIn.self, BadgeAck.self, BadgeAccount.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return ModelContext(container)
}

private func freshDefaults() -> UserDefaults {
    let name = "restorer-\(UUID().uuidString)"
    return UserDefaults(suiteName: name)!
}

/// Serves pages of check-ins like the server: oldest first, after a cursor.
private actor FakeSource: CheckInSource {
    var rows: [RemoteCheckIn]
    var failing = false
    private(set) var calls = 0
    private(set) var cursors: [UUID?] = []

    init(_ rows: [RemoteCheckIn]) { self.rows = rows }
    func fail(_ on: Bool) { failing = on }

    func myCheckIns(after cursor: (time: String, id: UUID)?, pageSize: Int) async throws -> [RemoteCheckIn] {
        calls += 1
        cursors.append(cursor?.id)
        if failing { throw URLError(.notConnectedToInternet) }
        let start = cursor.flatMap { c in rows.firstIndex { $0.id == c.id }.map { $0 + 1 } } ?? 0
        return Array(rows.dropFirst(start).prefix(pageSize))
    }
}

private func remote(_ n: Int, kind: String = "airport") -> RemoteCheckIn {
    RemoteCheckIn(
        id: UUID(uuidString: String(format: "00000000-0000-7000-8000-%012d", n))!, kind: kind,
        occurredAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(n)), cursorTime: "t\(n)",
        airportID: 3, airportCode: "FRA", visitContext: "departing"
    )
}

@MainActor
@Suite struct CheckInRestorerTests {
    let user = UUID()

    @Test func aDeviceWithoutCheckInsGetsTheOnesFromTheServerOnce() async throws {
        let context = try makeContext()
        let flight = RemoteCheckIn(
            id: UUID(), kind: "flown", occurredAt: Date(timeIntervalSince1970: 1_800_000_000), cursorTime: "t",
            originID: 3, destinationID: 9, originCode: "FRA", destinationCode: "JFK", flightNumber: "LH400", cabin: "economy", seat: "12A"
        )
        let source = FakeSource([flight, remote(1)])
        let restorer = CheckInRestorer(context: context, source: source, defaults: freshDefaults())

        #expect(await restorer.restore(userID: user) == .finished(stored: 2, rejected: 0))
        let all = try context.fetch(FetchDescriptor<LocalCheckIn>())
        #expect(all.count == 2)
        #expect(all.allSatisfy { $0.syncState == SyncState.synced.rawValue && $0.ownerID == user })
        let stats = CheckInStats(all, userID: user)
        #expect(stats.flights == 1)
        #expect(stats.airportVisits == 1)
        let restoredFlight = try #require(all.first { $0.kind == "flown" })
        #expect(restoredFlight.originCode == "FRA" && restoredFlight.seat == "12A")

        #expect(await restorer.restore(userID: user) == .idle)
        #expect(await source.calls == 1, "it asks only once per account")
    }

    @Test func aCheckInTheDeviceAlreadyHasIsLeftAlone() async throws {
        let context = try makeContext()
        let row = remote(1)
        context.insert(LocalCheckIn(
            id: row.id, kind: "spotted", registration: "D-AIMA", typeICAO: nil, typeName: nil, airportID: nil, airportCode: nil,
            latitude: nil, longitude: nil, occurredAt: Date(), syncState: .rejected, ownerID: user
        ))
        try context.save()
        let restorer = CheckInRestorer(context: context, source: FakeSource([row]), defaults: freshDefaults())

        #expect(await restorer.restore(userID: user) == .idle)
        let all = try context.fetch(FetchDescriptor<LocalCheckIn>())
        #expect(all.count == 1)
        #expect(all[0].kind == "spotted" && all[0].syncState == SyncState.rejected.rawValue)
    }

    @Test func morePagesAreFetchedUntilOneIsShort() async throws {
        let context = try makeContext()
        let rows = (1...(CheckInRestorer.pageSize + 1)).map { remote($0) }
        let source = FakeSource(rows)
        let restorer = CheckInRestorer(context: context, source: source, defaults: freshDefaults())

        #expect(await restorer.restore(userID: user) == .finished(stored: CheckInRestorer.pageSize + 1, rejected: 0))
        #expect(await source.cursors == [nil, rows[CheckInRestorer.pageSize - 1].id])
    }

    @Test func withoutNetworkItIsTriedAgainLater() async throws {
        let context = try makeContext()
        let source = FakeSource([remote(1)])
        await source.fail(true)
        let restorer = CheckInRestorer(context: context, source: source, defaults: freshDefaults())

        #expect(await restorer.restore(userID: user) == .retryLater(stored: 0, rejected: 0))
        #expect(restorer.wasRestored(for: user) == false)
        await source.fail(false)
        #expect(await restorer.restore(userID: user) == .finished(stored: 1, rejected: 0))
    }
}
