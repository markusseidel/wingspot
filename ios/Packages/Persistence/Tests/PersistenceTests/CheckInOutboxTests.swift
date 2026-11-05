import Foundation
import Persistence
import SwiftData
import Testing
import WingspotCore

@MainActor
private func makeContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: LocalCheckIn.self, BadgeAck.self, BadgeAccount.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return ModelContext(container)
}

/// Behaves like the real server: stores each id once, and can lose its answer on the way back.
private actor FakeServer: CheckInUploader {
    enum Fault { case none, networkDown, serverError(Int), loseAnswer }

    var fault = Fault.none
    var rejections: [UUID: String] = [:]
    var unknownStatus: Set<UUID> = []
    private(set) var stored: Set<UUID> = []
    private(set) var calls: [[UUID]] = []

    func set(_ fault: Fault) { self.fault = fault }
    func reject(_ id: UUID, code: String) { rejections[id] = code }
    func answerUnknown(_ id: UUID) { unknownStatus.insert(id) }

    func upload(_ items: [CheckInUploadItem]) async throws -> [CheckInUploadResult] {
        calls.append(items.map(\.id))
        switch fault {
        case .networkDown: throw URLError(.notConnectedToInternet)
        case .serverError(let status): throw APIError.unexpectedStatus(status)
        case .none, .loseAnswer: break
        }
        var results: [CheckInUploadResult] = []
        for item in items {
            if let code = rejections[item.id] {
                results.append(CheckInUploadResult(id: item.id, status: "rejected", code: code))
            } else if unknownStatus.contains(item.id) {
                results.append(CheckInUploadResult(id: item.id, status: "maybe"))
            } else {
                stored.insert(item.id)
                results.append(CheckInUploadResult(id: item.id, status: "stored"))
            }
        }
        if case .loseAnswer = fault { throw URLError(.networkConnectionLost) }
        return results
    }
}

private let alice = UUID()
private let bob = UUID()

@MainActor
private func save(_ context: ModelContext, _ registration: String, owner: UUID? = nil, at seconds: Double = 1_000) throws -> UUID {
    try CheckInStore(context: context).saveSpotted(
        SpottedDraft(registration: Registration(registration)), ownerID: owner, at: Date(timeIntervalSince1970: seconds)
    ).id
}

@MainActor
private func state(_ context: ModelContext, _ id: UUID) throws -> LocalCheckIn {
    try #require(try context.fetch(FetchDescriptor<LocalCheckIn>()).first { $0.id == id })
}

@MainActor struct CheckInOutboxTests {
    @Test func uploadsWhatWaitsAndMarksItSynced() async throws {
        let context = try makeContext()
        let id = try save(context, "DAIMA", owner: alice)
        let server = FakeServer()

        let outcome = await CheckInOutbox(context: context, uploader: server).sync(userID: alice)

        #expect(outcome == .finished(stored: 1, rejected: 0))
        #expect(try state(context, id).syncState == "synced")
        #expect(try state(context, id).syncedAt != nil)
        #expect(await server.stored == [id])
    }

    @Test func doesNothingWhenNothingWaits() async throws {
        let server = FakeServer()
        let outcome = await CheckInOutbox(context: try makeContext(), uploader: server).sync(userID: alice)
        #expect(outcome == .idle)
        #expect(await server.calls.isEmpty)
    }

    @Test func aLostAnswerNeverCreatesADuplicate() async throws {
        // The Milestone 3 test: the server stores the check-in, but the app never hears back.
        let context = try makeContext()
        let id = try save(context, "DAIMA", owner: alice)
        let server = FakeServer()
        let outbox = CheckInOutbox(context: context, uploader: server)

        await server.set(.loseAnswer)
        #expect(await outbox.sync(userID: alice) == .retryLater(stored: 0, rejected: 0))
        #expect(try state(context, id).syncState == "pending", "the app can't know the server has it")
        #expect(await server.stored == [id])

        await server.set(.none)
        #expect(await outbox.sync(userID: alice) == .finished(stored: 1, rejected: 0))
        #expect(try state(context, id).syncState == "synced")
        #expect(await server.stored == [id], "still exactly one on the server")
        #expect(await server.calls == [[id], [id]], "the retry used the same id")
    }

    @Test func aNetworkFailureKeepsEverythingPending() async throws {
        let context = try makeContext()
        let ids = [try save(context, "DAIMA", owner: alice), try save(context, "DAIMB", owner: alice, at: 2_000)]
        let server = FakeServer()
        await server.set(.networkDown)

        let outcome = await CheckInOutbox(context: context, uploader: server).sync(userID: alice)

        #expect(outcome == .retryLater(stored: 0, rejected: 0))
        for id in ids { #expect(try state(context, id).syncState == "pending") }
    }

    @Test func everyFailedRequestIsTriedAgain() async throws {
        // Including 404 (the endpoint isn't deployed yet) and 400: only an item's own answer can reject it.
        for status in [400, 401, 403, 404, 408, 413, 429, 500, 503] {
            let context = try makeContext()
            let id = try save(context, "DAIMA", owner: alice)
            let server = FakeServer()
            await server.set(.serverError(status))
            let outcome = await CheckInOutbox(context: context, uploader: server).sync(userID: alice)
            #expect(outcome == .retryLater(stored: 0, rejected: 0), "status \(status)")
            #expect(try state(context, id).syncState == "pending")
        }
    }

    @Test func aMissingEndpointNeverRejectsAnything() async throws {
        // Hosted has no sync endpoint until it is deployed. Nothing may be lost in the meantime.
        let context = try makeContext()
        let id = try save(context, "DAIMA", owner: alice)
        let server = FakeServer()
        await server.set(.serverError(404))
        let outbox = CheckInOutbox(context: context, uploader: server)

        _ = await outbox.sync(userID: alice)
        #expect(try state(context, id).syncState == "pending")
        #expect(try state(context, id).syncError == nil)

        await server.set(.none)
        #expect(await outbox.sync(userID: alice) == .finished(stored: 1, rejected: 0))
        #expect(try state(context, id).syncState == "synced")
    }

    @Test func oneRejectedItemDoesNotBlockTheOthers() async throws {
        let context = try makeContext()
        let bad = try save(context, "DAIMA", owner: alice)
        let good = try save(context, "DAIMB", owner: alice, at: 2_000)
        let server = FakeServer()
        await server.reject(bad, code: "unknown_type")

        let outcome = await CheckInOutbox(context: context, uploader: server).sync(userID: alice)

        #expect(outcome == .finished(stored: 1, rejected: 1))
        #expect(try state(context, bad).syncState == "rejected")
        #expect(try state(context, bad).syncError == "unknown_type")
        #expect(try state(context, good).syncState == "synced")
    }

    @Test func aRejectedItemStaysOnTheDeviceAndIsNotSentAgain() async throws {
        let context = try makeContext()
        let id = try save(context, "DAIMA", owner: alice)
        let server = FakeServer()
        await server.reject(id, code: "unknown_type")
        let outbox = CheckInOutbox(context: context, uploader: server)

        _ = await outbox.sync(userID: alice)
        #expect(await outbox.sync(userID: alice) == .idle)

        #expect(await server.calls.count == 1)
        #expect(try context.fetchCount(FetchDescriptor<LocalCheckIn>()) == 1, "nothing is deleted")
    }

    @Test func aStatusFromANewerServerLeavesTheItemWaiting() async throws {
        let context = try makeContext()
        let id = try save(context, "DAIMA", owner: alice)
        let server = FakeServer()
        await server.answerUnknown(id)

        let outcome = await CheckInOutbox(context: context, uploader: server).sync(userID: alice)

        #expect(outcome == .retryLater(stored: 0, rejected: 0))
        #expect(try state(context, id).syncState == "pending")
    }

    @Test func checkInsMadeSignedOutGoToWhoeverSignsInNext() async throws {
        let context = try makeContext()
        let id = try save(context, "DAIMA", owner: nil)
        let server = FakeServer()

        _ = await CheckInOutbox(context: context, uploader: server).sync(userID: alice)

        #expect(try state(context, id).ownerID == alice)
        #expect(try state(context, id).syncState == "synced")
    }

    @Test func aFailedAttemptStillClaimsSignedOutCheckInsForThatUser() async throws {
        let context = try makeContext()
        let id = try save(context, "DAIMA", owner: nil)
        let server = FakeServer()
        await server.set(.networkDown)
        let outbox = CheckInOutbox(context: context, uploader: server)

        _ = await outbox.sync(userID: alice)
        await server.set(.none)
        let forBob = await outbox.sync(userID: bob)

        #expect(forBob == .idle, "alice's check-in must not go to bob's account")
        #expect(await server.stored.isEmpty)
        #expect(try state(context, id).syncState == "pending")
    }

    @Test func anotherAccountsCheckInsStayOnTheDevice() async throws {
        let context = try makeContext()
        let alices = try save(context, "DAIMA", owner: alice)
        let bobs = try save(context, "DAIMB", owner: bob, at: 2_000)
        let server = FakeServer()

        _ = await CheckInOutbox(context: context, uploader: server).sync(userID: bob)

        #expect(await server.stored == [bobs])
        #expect(try state(context, alices).syncState == "pending")
    }

    @Test func sendsOldestFirstInBatchesOfFifty() async throws {
        let context = try makeContext()
        var ids: [UUID] = []
        for index in 0..<120 {
            ids.append(try save(context, "DAIMA", owner: alice, at: Double(index)))
        }
        let server = FakeServer()

        let outcome = await CheckInOutbox(context: context, uploader: server).sync(userID: alice)

        #expect(outcome == .finished(stored: 120, rejected: 0))
        let calls = await server.calls
        #expect(calls.map(\.count) == [50, 50, 20])
        #expect(calls.flatMap { $0 } == ids)
    }

    @Test func partlyUploadedWorkContinuesWhereItStopped() async throws {
        let context = try makeContext()
        for index in 0..<3 { _ = try save(context, "DAIMA", owner: alice, at: Double(index)) }
        let server = FakeServer()
        let outbox = CheckInOutbox(context: context, uploader: server)
        await server.set(.networkDown)
        _ = await outbox.sync(userID: alice)
        await server.set(.none)

        #expect(await outbox.sync(userID: alice) == .finished(stored: 3, rejected: 0))
        #expect(try outbox.pendingCount(for: alice) == 0)
    }
}

@MainActor struct CheckInSyncCoordinatorTests {
    private func coordinator(
        _ context: ModelContext, server: FakeServer, user: UUID?, sleeps: SleepLog = SleepLog()
    ) -> CheckInSyncCoordinator {
        CheckInSyncCoordinator(
            outbox: CheckInOutbox(context: context, uploader: server), userID: { user },
            backoff: [.seconds(1), .seconds(2)], sleep: { await sleeps.record($0) }
        )
    }

    @Test func doesNothingWhileSignedOut() async throws {
        let context = try makeContext()
        let id = try save(context, "DAIMA")
        let server = FakeServer()
        let sync = coordinator(context, server: server, user: nil)

        sync.requestSync()
        await sync.waitUntilIdle()

        #expect(await server.calls.isEmpty)
        #expect(try state(context, id).syncState == "pending")
    }

    @Test func uploadsAfterARequest() async throws {
        let context = try makeContext()
        let id = try save(context, "DAIMA", owner: alice)
        let server = FakeServer()
        let sync = coordinator(context, server: server, user: alice)

        sync.requestSync()
        await sync.waitUntilIdle()

        #expect(try state(context, id).syncState == "synced")
    }

    @Test func manyRequestsAtOnceMakeOneRun() async throws {
        let context = try makeContext()
        _ = try save(context, "DAIMA", owner: alice)
        let server = FakeServer()
        let sync = coordinator(context, server: server, user: alice)

        for _ in 0..<5 { sync.requestSync() }
        await sync.waitUntilIdle()

        #expect(await server.calls.count <= 2, "the first run, plus at most one follow-up")
        #expect(await server.stored.count == 1)
    }

    @Test func retriesWithGrowingPausesAndThenStops() async throws {
        let context = try makeContext()
        let id = try save(context, "DAIMA", owner: alice)
        let server = FakeServer()
        await server.set(.networkDown)
        let sleeps = SleepLog()
        let sync = coordinator(context, server: server, user: alice, sleeps: sleeps)

        sync.requestSync()
        await sync.waitUntilIdle()

        #expect(await sleeps.durations == [.seconds(1), .seconds(2)])
        #expect(await server.calls.count == 3, "the first try and one per pause")
        #expect(try state(context, id).syncState == "pending")
        #expect(!sync.isWaitingToRetry)
    }

    @Test func theAfterRunHookRunsAfterASuccessfulRunButNotAfterAFailedOne() async throws {
        let context = try makeContext()
        _ = try save(context, "DAIMA", owner: alice)
        let server = FakeServer()
        let counter = RunCounter()
        let sync = CheckInSyncCoordinator(
            outbox: CheckInOutbox(context: context, uploader: server), userID: { alice },
            backoff: [], sleep: { _ in }, afterRun: { counter.count += 1 }
        )

        await server.set(.networkDown)
        sync.requestSync()
        await sync.waitUntilIdle()
        #expect(counter.count == 0, "a failed run says nothing new")

        await server.set(.none)
        sync.requestSync()
        await sync.waitUntilIdle()
        #expect(counter.count == 1)

        sync.requestSync()
        await sync.waitUntilIdle()
        #expect(counter.count == 2, "even with nothing to upload, the server may know something new")
    }

    @Test func aRetryThatWorksEndsTheWaiting() async throws {
        let context = try makeContext()
        let id = try save(context, "DAIMA", owner: alice)
        let server = FakeServer()
        await server.set(.networkDown)
        let sync = CheckInSyncCoordinator(
            outbox: CheckInOutbox(context: context, uploader: server), userID: { alice },
            backoff: [.seconds(1)], sleep: { _ in await server.set(.none) }
        )

        sync.requestSync()
        await sync.waitUntilIdle()

        #expect(try state(context, id).syncState == "synced")
    }
}

private actor SleepLog {
    private(set) var durations: [Duration] = []
    func record(_ duration: Duration) { durations.append(duration) }
}

@MainActor private final class RunCounter { var count = 0 }
