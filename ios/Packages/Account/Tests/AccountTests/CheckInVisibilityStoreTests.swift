import Foundation
import Testing
@testable import Account

private actor FakeVisibility: CheckInVisibilityBackend {
    var stored: [UUID: CheckInVisibility] = [:]
    var accountLevel: SharingChoice = .friends
    var sent: [SharingChoice?] = []
    var failing = false

    init(_ id: UUID, _ visibility: CheckInVisibility) { stored[id] = visibility }
    func fail(_ on: Bool) { failing = on }

    func checkInVisibility(_ id: UUID) throws -> CheckInVisibility? {
        if failing { throw AccountError.offline }
        return stored[id]
    }

    func setCheckInVisibility(_ id: UUID, to choice: SharingChoice?) throws -> SharingChoice? {
        if failing { throw AccountError.offline }
        guard stored[id] != nil else { return nil }
        sent.append(choice)
        stored[id] = CheckInVisibility(level: choice ?? accountLevel, isCustom: choice != nil)
        return stored[id]?.level
    }
}

private let mine = UUID()

@MainActor @Test func theLevelOfOneCheckInIsRead() async throws {
    let store = CheckInVisibilityStore(backend: FakeVisibility(mine, CheckInVisibility(level: .friends, isCustom: false)))
    let read = try await store.visibility(of: mine)
    #expect(read == CheckInVisibility(level: .friends, isCustom: false))
    #expect(try await store.visibility(of: UUID()) == nil)
}

@MainActor @Test func settingALevelMarksItAsSetByHandAndGoingBackFollowsTheAccount() async throws {
    let backend = FakeVisibility(mine, CheckInVisibility(level: .friends, isCustom: false))
    let store = CheckInVisibilityStore(backend: backend)
    let set = try await store.set(.followers, for: mine)
    #expect(set == CheckInVisibility(level: .followers, isCustom: true))
    let back = try await store.set(nil, for: mine)
    #expect(back == CheckInVisibility(level: .friends, isCustom: false))
    #expect(await backend.sent == [.followers, nil])
}

@MainActor @Test func aCheckInThatIsNotYoursChangesNothing() async throws {
    let store = CheckInVisibilityStore(backend: FakeVisibility(mine, CheckInVisibility(level: .private, isCustom: false)))
    #expect(try await store.set(.public, for: UUID()) == nil)
}

@MainActor @Test func aFailureReachesTheCaller() async {
    let backend = FakeVisibility(mine, CheckInVisibility(level: .private, isCustom: false))
    await backend.fail(true)
    let store = CheckInVisibilityStore(backend: backend)
    await #expect(throws: AccountError.self) { _ = try await store.set(.public, for: mine) }
}
