import Foundation
import Persistence
import SwiftData
import Testing
import WingspotCore

@MainActor
private func makeContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: LocalCheckIn.self, BadgeAck.self, BadgeAccount.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return ModelContext(container)
}

private let user = UUID()
private let other = UUID()
private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func iso(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

/// The server's answer for badges given as (id, level, unlocked at).
private func answer(_ badges: [(String, Int, Date?)]) throws -> (progress: UserProgress, raw: Data) {
    let items = badges.map { id, level, at in
        """
        {"id":"\(id)","name":{"en":"\(id)"},"category":"milestones","hidden":false,"levels":[1,5,10],
         "value":\(level),"level":\(level),"unlocked_at":\(at.map { "\"\(iso($0))\"" } ?? "null")}
        """
    }
    let raw = Data("""
    {"xp":100,"level":2,"xp_for_level":100,"xp_for_next_level":300,"hidden_remaining":0,"badges":[\(items.joined(separator: ","))]}
    """.utf8)
    return (try UserProgress.decode(raw), raw)
}

private actor FakeSource: ProgressSource {
    var next: Result<(progress: UserProgress, raw: Data), Error> = .failure(URLError(.notConnectedToInternet))
    private(set) var calls = 0
    func set(_ result: Result<(progress: UserProgress, raw: Data), Error>) { next = result }
    func progress() async throws -> (progress: UserProgress, raw: Data) {
        calls += 1
        return try next.get()
    }
}

@MainActor private func store(_ context: ModelContext, _ source: FakeSource, at date: Date = now) -> BadgeStore {
    BadgeStore(context: context, source: source, now: { date })
}

@MainActor struct BadgeStoreTests {
    @Test func aBadgeUnlockedAfterTheAccountAppearedIsCelebrated() async throws {
        let source = FakeSource()
        let badges = store(try makeContext(), source)
        badges.begin(userID: user)
        await source.set(.success(try answer([("wheels_up", 1, now.addingTimeInterval(60))])))

        await badges.refresh()

        #expect(badges.celebrations.map(\.badge.id) == ["wheels_up"])
        #expect(badges.celebrations.first?.previousLevel == 0)
        #expect(badges.progress?.level == 2)
    }

    @Test func badgesFromBeforeTheAccountAppearedHereAreNotCelebratedAgain() async throws {
        // A reinstall or a new phone: the server already has these.
        let source = FakeSource()
        let badges = store(try makeContext(), source)
        badges.begin(userID: user)
        await source.set(.success(try answer([("wheels_up", 1, now.addingTimeInterval(-86_400 * 30))])))

        await badges.refresh()

        #expect(badges.celebrations.isEmpty)
        #expect(badges.progress != nil)
    }

    @Test func aSlightlyWrongClockStillCelebratesTheFirstBadge() async throws {
        let source = FakeSource()
        let badges = store(try makeContext(), source)
        badges.begin(userID: user)
        await source.set(.success(try answer([("wheels_up", 1, now.addingTimeInterval(-120))])))

        await badges.refresh()

        #expect(badges.celebrations.map(\.badge.id) == ["wheels_up"])
    }

    @Test func aCelebrationShowsOnceAfterItWasAcknowledged() async throws {
        let source = FakeSource()
        let badges = store(try makeContext(), source)
        badges.begin(userID: user)
        let unlocked = try answer([("wheels_up", 1, now.addingTimeInterval(60))])
        await source.set(.success(unlocked))
        await badges.refresh()

        badges.acknowledge()
        #expect(badges.celebrations.isEmpty)

        await badges.refresh()
        #expect(badges.celebrations.isEmpty, "the same level isn't celebrated twice")
    }

    @Test func aHigherLevelIsCelebratedWithItsPreviousLevel() async throws {
        let source = FakeSource()
        let badges = store(try makeContext(), source)
        badges.begin(userID: user)
        await source.set(.success(try answer([("logbook", 1, now.addingTimeInterval(60))])))
        await badges.refresh()
        badges.acknowledge()

        await source.set(.success(try answer([("logbook", 2, now.addingTimeInterval(120))])))
        await badges.refresh()

        #expect(badges.celebrations.map(\.badge.level) == [2])
        #expect(badges.celebrations.first?.previousLevel == 1)
    }

    @Test func aCelebrationThatWasNotAcknowledgedComesBackAfterARelaunch() async throws {
        // The app closed before the user saw it. The server still says it's unlocked, so it is shown next time.
        let context = try makeContext()
        let source = FakeSource()
        let first = store(context, source)
        first.begin(userID: user)
        await source.set(.success(try answer([("wheels_up", 1, now.addingTimeInterval(60))])))
        await first.refresh()
        #expect(first.celebrations.count == 1)

        let relaunched = store(context, source)
        relaunched.begin(userID: user)
        await relaunched.refresh()

        #expect(relaunched.celebrations.map(\.badge.id) == ["wheels_up"])
    }

    @Test func aLostUploadAnswerLosesNothing() async throws {
        // Nothing here depends on an upload answer: the unlock only has to be on the server.
        let source = FakeSource()
        let badges = store(try makeContext(), source)
        badges.begin(userID: user)
        await source.set(.success(try answer([("wheels_up", 1, now.addingTimeInterval(10)), ("old_friend", 2, now.addingTimeInterval(20))])))

        await badges.refresh()

        #expect(badges.celebrations.map(\.badge.id) == ["wheels_up", "old_friend"])
    }

    @Test func aFailedRefreshKeepsTheLastProgressAndSaysSo() async throws {
        let context = try makeContext()
        let source = FakeSource()
        let badges = store(context, source)
        badges.begin(userID: user)
        await source.set(.success(try answer([("wheels_up", 1, now.addingTimeInterval(-86_400))])))
        await badges.refresh()
        #expect(badges.progress != nil && !badges.refreshFailed)

        await source.set(.failure(URLError(.notConnectedToInternet)))
        await badges.refresh()

        #expect(badges.refreshFailed)
        #expect(badges.progress?.badges.map(\.id) == ["wheels_up"])
    }

    @Test func theLastProgressIsThereAfterARelaunchWithoutANetwork() async throws {
        let context = try makeContext()
        let source = FakeSource()
        let first = store(context, source)
        first.begin(userID: user)
        await source.set(.success(try answer([("wheels_up", 1, now.addingTimeInterval(-86_400))])))
        await first.refresh()

        let relaunched = store(context, FakeSource())
        relaunched.begin(userID: user)

        #expect(relaunched.progress?.badges.map(\.id) == ["wheels_up"])
        #expect(relaunched.celebrations.isEmpty)
    }

    @Test func eachAccountHasItsOwnState() async throws {
        let context = try makeContext()
        let source = FakeSource()
        let badges = store(context, source)
        badges.begin(userID: user)
        await source.set(.success(try answer([("wheels_up", 1, now.addingTimeInterval(60))])))
        await badges.refresh()
        badges.acknowledge()

        badges.begin(userID: other)
        #expect(badges.progress == nil && badges.celebrations.isEmpty, "nothing of the other account is shown")
        await badges.refresh()
        #expect(badges.celebrations.map(\.badge.id) == ["wheels_up"], "the second account hasn't seen it yet")

        badges.begin(userID: nil)
        #expect(badges.progress == nil && badges.celebrations.isEmpty)
    }

    @Test func nothingHappensSignedOut() async throws {
        let source = FakeSource()
        let badges = store(try makeContext(), source)
        badges.begin(userID: nil)
        await badges.refresh()
        #expect(await source.calls == 0)
    }

    @Test func hiddenBadgesAppearOnlyWhenTheServerSendsThem() async throws {
        let source = FakeSource()
        let badges = store(try makeContext(), source)
        badges.begin(userID: user)
        await source.set(.success(try answer([("logbook", 0, nil)])))
        await badges.refresh()
        #expect(badges.celebrations.isEmpty, "a badge at level 0 is nothing to celebrate")
    }
}
