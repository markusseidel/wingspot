import Foundation
import Testing
@testable import Account

private actor FakePushBackend: PushBackend {
    private(set) var registered: [DeviceRegistration] = []
    private(set) var removed: [UUID] = []
    var stored = NotificationPrefs()
    var failure: AccountError?
    private(set) var saved: [NotificationPrefs] = []

    func fail(_ error: AccountError?) { failure = error }

    func registerDevice(_ device: DeviceRegistration) throws {
        if let failure { throw failure }
        registered.append(device)
    }
    func removeDevice(id: UUID) throws { removed.append(id) }
    func notificationPrefs(of me: UUID) throws -> NotificationPrefs {
        if let failure { throw failure }
        return stored
    }
    func setNotificationPrefs(_ prefs: NotificationPrefs, as me: UUID) throws {
        if let failure { throw failure }
        saved.append(prefs)
    }
}

private final class FakeSystem: PushSystem, @unchecked Sendable {
    private let lock = NSLock()
    private var status: PushAuthorization
    private var answer: Bool
    private var asked = 0
    private var registrations = 0

    init(status: PushAuthorization, answer: Bool = true) {
        self.status = status
        self.answer = answer
    }

    var requestCount: Int { lock.withLock { asked } }
    var tokenRequests: Int { lock.withLock { registrations } }

    func authorization() async -> PushAuthorization { lock.withLock { status } }
    func requestAuthorization() async -> Bool {
        lock.withLock {
            asked += 1
            status = answer ? .allowed : .denied
            return answer
        }
    }
    func registerForRemoteNotifications() { lock.withLock { registrations += 1 } }
}

private let me = UUID()

@MainActor private func makeStore(
    _ backend: FakePushBackend, _ system: FakeSystem, signedIn: Bool = true, defaults: UserDefaults? = nil
) -> PushStore {
    let defaults = defaults ?? UserDefaults(suiteName: "push-\(UUID().uuidString)")!
    return PushStore(
        backend: backend, system: system, defaults: defaults, environment: .sandbox,
        device: { ("0.2.0", "18.1", "de-DE") }, userID: { signedIn ? me : nil }
    )
}

private let token = Data([0xAB, 0x01, 0xFF])

@MainActor @Test func aTokenIsSentToTheServerWithThisPhonesDetails() async {
    let backend = FakePushBackend()
    let store = makeStore(backend, FakeSystem(status: .allowed))
    await store.sync()
    await store.didReceive(token: token)
    let sent = await backend.registered
    #expect(sent.count == 1)
    #expect(sent.first?.token == "ab01ff")
    #expect(sent.first?.environment == .sandbox)
    #expect(sent.first?.locale == "de-DE")
    #expect(sent.first?.id == store.deviceID)
}

@MainActor @Test func theSameTokenIsNotSentTwice() async {
    let backend = FakePushBackend()
    let store = makeStore(backend, FakeSystem(status: .allowed))
    await store.didReceive(token: token)
    await store.sync()
    await store.didReceive(token: token)
    #expect(await backend.registered.count == 1)
}

@MainActor @Test func aTokenThatArrivesBeforeSignInIsSentAfterwards() async {
    let backend = FakePushBackend()
    var signedIn = false
    let system = FakeSystem(status: .allowed)
    let store = PushStore(
        backend: backend, system: system, defaults: UserDefaults(suiteName: "push-\(UUID().uuidString)")!,
        environment: .production, device: { ("0.2.0", "18.1", "en-US") }, userID: { signedIn ? me : nil }
    )
    await store.didReceive(token: token)
    #expect(await backend.registered.isEmpty)
    signedIn = true
    await store.sync()
    #expect(await backend.registered.count == 1)
}

@MainActor @Test func nothingIsSentWithoutPermission() async {
    let backend = FakePushBackend()
    let system = FakeSystem(status: .denied)
    let store = makeStore(backend, system)
    await store.sync()
    #expect(store.authorization == .denied)
    #expect(system.tokenRequests == 0, "no token is asked for without permission")
}

@MainActor @Test func aFailedRegistrationIsTriedAgainNextTime() async {
    let backend = FakePushBackend()
    await backend.fail(.offline)
    let store = makeStore(backend, FakeSystem(status: .allowed))
    await store.didReceive(token: token)
    #expect(await backend.registered.isEmpty)
    await backend.fail(nil)
    await store.sync()
    #expect(await backend.registered.count == 1)
}

@MainActor @Test func theDeviceIDStaysTheSame() {
    let defaults = UserDefaults(suiteName: "push-\(UUID().uuidString)")!
    let backend = FakePushBackend()
    let first = makeStore(backend, FakeSystem(status: .allowed), defaults: defaults).deviceID
    let second = makeStore(backend, FakeSystem(status: .allowed), defaults: defaults).deviceID
    #expect(first == second)
}

@MainActor @Test func removingTheDeviceTellsTheServerAndAllowsANewRegistration() async {
    let backend = FakePushBackend()
    let store = makeStore(backend, FakeSystem(status: .allowed))
    await store.didReceive(token: token)
    await store.removeDevice()
    #expect(await backend.removed == [store.deviceID])
    await store.didReceive(token: token)
    #expect(await backend.registered.count == 2)
}

@MainActor @Test func enablingAsksTheSystemAndThenRegisters() async {
    let backend = FakePushBackend()
    let system = FakeSystem(status: .notDetermined)
    let store = makeStore(backend, system)
    #expect(await store.enable())
    #expect(system.requestCount == 1)
    #expect(store.authorization == .allowed)
    #expect(system.tokenRequests == 1)
}

@MainActor @Test func sayingNoLeavesNotificationsOff() async {
    let system = FakeSystem(status: .notDetermined, answer: false)
    let store = makeStore(FakePushBackend(), system)
    #expect(await store.enable() == false)
    #expect(store.authorization == .denied)
}

@MainActor @Test func theQuestionIsAskedOnceAfterTheFirstSocialAction() async {
    let store = makeStore(FakePushBackend(), FakeSystem(status: .notDetermined))
    await store.socialActionHappened()
    #expect(store.isAsking)
    store.isAsking = false
    await store.socialActionHappened()
    #expect(!store.isAsking, "never again once it was shown")
}

@MainActor @Test func nobodyIsAskedWhoAnsweredAlready() async {
    let store = makeStore(FakePushBackend(), FakeSystem(status: .allowed))
    await store.socialActionHappened()
    #expect(!store.isAsking)
    let denied = makeStore(FakePushBackend(), FakeSystem(status: .denied))
    await denied.socialActionHappened()
    #expect(!denied.isAsking)
}

@MainActor @Test func choicesAreShownAtOnceAndGoBackWhenTheServerRefuses() async {
    let backend = FakePushBackend()
    let store = makeStore(backend, FakeSystem(status: .allowed))
    await store.loadPrefs()
    #expect(store.prefs == NotificationPrefs())
    await store.setPrefs(NotificationPrefs(newFollowers: true, salutes: false, comments: true))
    #expect(store.prefs?.salutes == false)
    #expect(await backend.saved.count == 1)
    await backend.fail(.offline)
    await store.setPrefs(NotificationPrefs(newFollowers: false, salutes: false, comments: true))
    #expect(store.prefs?.newFollowers == true, "back to what the server has")
    #expect(store.failure != nil)
}
