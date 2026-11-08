import Foundation
import Observation

/// Which notifications a person wants. Stored on the server, so the server never sends the others.
public struct NotificationPrefs: Equatable, Sendable {
    public var newFollowers: Bool
    public var salutes: Bool
    public var comments: Bool

    public init(newFollowers: Bool = true, salutes: Bool = true, comments: Bool = true) {
        self.newFollowers = newFollowers
        self.salutes = salutes
        self.comments = comments
    }
}

/// This installation of the app, as the server needs it to send a notification.
public struct DeviceRegistration: Equatable, Sendable {
    public enum Environment: String, Sendable { case sandbox, production }

    public let id: UUID
    public let token: String
    public let environment: Environment
    public let appVersion: String
    public let osVersion: String
    /// The phone's first language, such as `de-DE`. The server writes the notification in it.
    public let locale: String

    public init(id: UUID, token: String, environment: Environment, appVersion: String, osVersion: String, locale: String) {
        self.id = id
        self.token = token
        self.environment = environment
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.locale = locale
    }
}

public protocol PushBackend: Sendable {
    func registerDevice(_ device: DeviceRegistration) async throws
    func removeDevice(id: UUID) async throws
    func notificationPrefs(of me: UUID) async throws -> NotificationPrefs
    func setNotificationPrefs(_ prefs: NotificationPrefs, as me: UUID) async throws
}

/// What the phone says about notifications.
public enum PushAuthorization: Equatable, Sendable {
    case notDetermined, denied, allowed
}

/// The parts that belong to the phone, so tests don't need one.
public protocol PushSystem: Sendable {
    func authorization() async -> PushAuthorization
    /// Shows the system question. Returns whether the person said yes.
    func requestAuthorization() async -> Bool
    /// Asks the system for a token. It arrives later, through `PushStore.didReceive(token:)`.
    @MainActor func registerForRemoteNotifications()
}

/// Notification permission, the token and the person's choices.
@MainActor
@Observable
public final class PushStore {
    public private(set) var authorization = PushAuthorization.notDetermined
    /// True while the app should explain notifications and ask. Set after the first follow, salute or comment.
    public var isAsking = false
    public private(set) var prefs: NotificationPrefs?
    public private(set) var failure: AccountError?

    private let backend: PushBackend
    private let system: PushSystem
    private let defaults: UserDefaults
    private let userID: @MainActor () -> UUID?
    private let device: () -> (appVersion: String, osVersion: String, locale: String)
    private let environment: DeviceRegistration.Environment
    private var token: String?
    /// The user and token last sent to the server, so the same thing isn't sent again and again.
    private var registered: (user: UUID, token: String)?

    private static let deviceKey = "pushDeviceID"
    private static let askedKey = "pushPromptShown"

    public init(
        backend: PushBackend, system: PushSystem, defaults: UserDefaults = .standard,
        environment: DeviceRegistration.Environment,
        device: @escaping () -> (appVersion: String, osVersion: String, locale: String),
        userID: @escaping @MainActor () -> UUID?
    ) {
        self.backend = backend
        self.system = system
        self.defaults = defaults
        self.environment = environment
        self.device = device
        self.userID = userID
    }

    /// One ID per installation, kept across sign-ins.
    public var deviceID: UUID {
        if let text = defaults.string(forKey: Self.deviceKey), let id = UUID(uuidString: text) { return id }
        let id = UUID()
        defaults.set(id.uuidString, forKey: Self.deviceKey)
        return id
    }

    /// Reads the permission, asks the system for a token when allowed, and tells the server about this phone.
    /// Call it at launch, after signing in, and when the app comes to the foreground.
    public func sync() async {
        authorization = await system.authorization()
        guard authorization == .allowed, let me = userID() else { return }
        system.registerForRemoteNotifications()
        await register(for: me)
    }

    /// The system's token, as a hex string.
    public func didReceive(token data: Data) async {
        token = data.map { String(format: "%02x", $0) }.joined()
        guard let me = userID() else { return }
        await register(for: me)
    }

    private func register(for me: UUID) async {
        guard let token, registered?.user != me || registered?.token != token else { return }
        let info = device()
        let registration = DeviceRegistration(
            id: deviceID, token: token, environment: environment,
            appVersion: info.appVersion, osVersion: info.osVersion, locale: info.locale
        )
        do {
            try await backend.registerDevice(registration)
            registered = (me, token)
        } catch {
            // Tried again at the next start or when the app comes back.
        }
    }

    /// Stops notifications for this phone. Call it before signing out, while the session still works.
    public func removeDevice() async {
        registered = nil
        try? await backend.removeDevice(id: deviceID)
    }

    /// Shows the system question. Returns whether notifications are now on.
    @discardableResult
    public func enable() async -> Bool {
        let granted = await system.requestAuthorization()
        await sync()
        return granted
    }

    /// Called after the person's first follow, salute or comment: a good moment to ask, once.
    public func socialActionHappened() async {
        guard !defaults.bool(forKey: Self.askedKey) else { return }
        authorization = await system.authorization()
        guard authorization == .notDetermined else { return }
        defaults.set(true, forKey: Self.askedKey)
        isAsking = true
    }

    public func loadPrefs() async {
        guard let me = userID() else { return }
        do {
            prefs = try await backend.notificationPrefs(of: me)
            failure = nil
        } catch {
            failure = (error as? AccountError) ?? .unknown
        }
    }

    /// Shows the change at once and goes back if the server refuses.
    public func setPrefs(_ new: NotificationPrefs) async {
        guard let me = userID(), let before = prefs, new != before else { return }
        prefs = new
        do {
            try await backend.setNotificationPrefs(new, as: me)
            failure = nil
        } catch {
            prefs = before
            failure = (error as? AccountError) ?? .unknown
        }
    }

    /// Forgets what belongs to the signed-in person.
    public func clear() {
        prefs = nil
        failure = nil
        registered = nil
    }
}
