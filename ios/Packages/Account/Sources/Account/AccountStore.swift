import Foundation
import Observation

public enum AccountError: Error, Equatable, Sendable {
    case invalidEmail
    case invalidUsername
    case usernameTaken
    /// The sign-in link was used already, has expired, or was requested on another device.
    case invalidLink
    case tooManyRequests
    /// Sign in with Apple isn't switched on at the backend yet.
    case appleUnavailable
    case offline
    /// A comment the word filter refuses.
    case contentNotAllowed
    /// This build has no backend key, see ios/Config/Wingspot.xcconfig.
    case notConfigured
    case unknown
}

/// What the app needs from the backend. Lets tests run without a network.
public protocol AccountBackend: Sendable {
    /// The user with a session stored on this device. Doesn't need a network.
    func currentUserID() async -> UUID?
    /// An access token for the Wingspot API, refreshed if it expired. `nil` if nobody is signed in or the refresh failed.
    func accessToken() async -> String?
    func sendSignInLink(email: String, language: String?) async throws
    /// Finishes sign-in from the link in the email and returns the user's ID.
    func completeSignIn(from url: URL) async throws -> UUID
    /// Signs in with the identity token from Sign in with Apple. `nonce` is the unhashed value whose SHA-256 went into the request.
    func signInWithApple(idToken: String, nonce: String) async throws -> UUID
    func loadProfile(id: UUID) async throws -> Profile
    func saveProfile(_ profile: Profile) async throws
    func signOut() async throws
    /// Deletes the account on the server, for good. The session stops working.
    func deleteAccount() async throws
    /// The person's own data as the server sends it, one JSON document.
    func exportMyData() async throws -> Data
}

/// The app's sign-in state. Check-ins don't depend on it, so the app also works signed out and offline.
@MainActor
@Observable
public final class AccountStore {
    public enum State: Equatable, Sendable {
        case loading
        case signedOut
        /// `nil` until the profile loads. It stays `nil` while offline.
        case signedIn(Profile?)
    }

    public private(set) var state = State.loading
    /// Why the last sign-in link didn't work, for the app to show.
    public var linkError: AccountError?
    /// The name Apple gave at the first sign-in, to prefill the profile. Apple sends it only once, and never again.
    public private(set) var suggestedName: String?
    /// The signed-in user, known from the stored session even while offline. `nil` when signed out.
    public private(set) var userID: UUID?

    private let backend: AccountBackend

    public init(backend: AccountBackend) {
        self.backend = backend
    }

    public var profile: Profile? {
        if case .signedIn(let profile) = state { profile } else { nil }
    }

    /// True once the user has to pick a username before going on.
    public var needsProfileSetup: Bool {
        profile.map { !$0.hasChosenUsername } ?? false
    }

    /// Restores the stored session. A failed profile load keeps the user signed in.
    public func start() async {
        guard let id = await backend.currentUserID() else {
            userID = nil
            state = .signedOut
            return
        }
        userID = id
        state = .signedIn(nil)
        await loadProfile(id: id)
    }

    public func reloadProfile() async {
        await start()
    }

    public func sendSignInLink(email: String, language: String?) async throws {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard EmailAddress.isPlausible(email) else { throw AccountError.invalidEmail }
        try await backend.sendSignInLink(email: email, language: language)
    }

    /// Handles a link opened from outside the app. Never log these URLs, they can carry sign-in codes.
    /// - Returns: `false` if this isn't a sign-in link.
    @discardableResult
    public func handle(_ url: URL) async -> Bool {
        guard url.scheme == "wingspot", url.host == "auth-callback" else { return false }
        do {
            let id = try await backend.completeSignIn(from: url)
            linkError = nil
            userID = id
            state = .signedIn(nil)
            await loadProfile(id: id)
        } catch {
            linkError = error as? AccountError ?? .unknown
        }
        return true
    }

    /// For API calls that need the signed-in user. Refreshes an expired token.
    public func accessToken() async -> String? {
        await backend.accessToken()
    }

    /// Finishes Sign in with Apple. Never log the token.
    /// - Parameter fullName: Apple's name for the user, which it only gives the first time.
    public func signInWithApple(idToken: String, nonce: String, fullName: String?) async throws {
        let id = try await backend.signInWithApple(idToken: idToken, nonce: nonce)
        let name = fullName?.trimmingCharacters(in: .whitespacesAndNewlines)
        suggestedName = (name?.isEmpty ?? true) ? nil : name
        linkError = nil
        userID = id
        state = .signedIn(nil)
        await loadProfile(id: id)
    }

    /// For the profile form to use once, then forget.
    public func takeSuggestedName() -> String? {
        defer { suggestedName = nil }
        return suggestedName
    }

    public func save(_ profile: Profile) async throws {
        guard Username.isValid(profile.username) else { throw AccountError.invalidUsername }
        try await backend.saveProfile(profile)
        state = .signedIn(profile)
    }

    /// Local check-ins stay on the device.
    public func signOut() async throws {
        try await backend.signOut()
        userID = nil
        state = .signedOut
    }

    /// Deletes the account on the server and signs out here. Check-ins on the phone are for the app to remove,
    /// with the returned ID. Nothing changes here if the server fails.
    /// - Returns: the deleted account's ID.
    @discardableResult
    public func deleteAccount() async throws -> UUID {
        guard let id = userID else { throw AccountError.unknown }
        try await backend.deleteAccount()
        // The server already ended the session, so this only clears what is stored on the phone.
        try? await backend.signOut()
        userID = nil
        state = .signedOut
        return id
    }

    /// The person's data as readable JSON, for them to save or share.
    public func exportData() async throws -> Data {
        let raw = try await backend.exportMyData()
        guard let object = try? JSONSerialization.jsonObject(with: raw),
              let pretty = try? JSONSerialization.data(
                  withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              )
        else { throw AccountError.unknown }
        return pretty
    }

    private func loadProfile(id: UUID) async {
        do {
            state = .signedIn(try await backend.loadProfile(id: id))
        } catch {
            // The client removes a session the server rejected. Anything else, such as being offline,
            // leaves the user signed in.
            if await backend.currentUserID() == nil {
                userID = nil
                state = .signedOut
            }
        }
    }
}

/// For builds without a backend key. The app still works, except for signing in.
public struct UnconfiguredAccountBackend: AccountBackend, SocialBackend, FeedBackend, ReactionBackend, PushBackend {
    public init() {}

    public func currentUserID() async -> UUID? { nil }
    public func accessToken() async -> String? { nil }
    public func sendSignInLink(email: String, language: String?) async throws { throw AccountError.notConfigured }
    public func completeSignIn(from url: URL) async throws -> UUID { throw AccountError.notConfigured }
    public func signInWithApple(idToken: String, nonce: String) async throws -> UUID { throw AccountError.notConfigured }
    public func loadProfile(id: UUID) async throws -> Profile { throw AccountError.notConfigured }
    public func saveProfile(_ profile: Profile) async throws { throw AccountError.notConfigured }
    public func signOut() async throws { throw AccountError.notConfigured }
    public func deleteAccount() async throws { throw AccountError.notConfigured }
    public func exportMyData() async throws -> Data { throw AccountError.notConfigured }

    public func registerDevice(_ device: DeviceRegistration) async throws { throw AccountError.notConfigured }
    public func removeDevice(id: UUID) async throws { throw AccountError.notConfigured }
    public func notificationPrefs(of me: UUID) async throws -> NotificationPrefs { throw AccountError.notConfigured }
    public func setNotificationPrefs(_ prefs: NotificationPrefs, as me: UUID) async throws { throw AccountError.notConfigured }

    public func searchPeople(_ text: String, excluding me: UUID, limit: Int) async throws -> [PersonRecord] { throw AccountError.notConfigured }
    public func relationships(of me: UUID, among ids: [UUID]) async throws -> (following: Set<UUID>, followers: Set<UUID>) { throw AccountError.notConfigured }
    public func followingIDs(of me: UUID) async throws -> [UUID] { throw AccountError.notConfigured }
    public func followerIDs(of me: UUID) async throws -> [UUID] { throw AccountError.notConfigured }
    public func profiles(ids: [UUID]) async throws -> [PersonRecord] { throw AccountError.notConfigured }
    public func follow(_ id: UUID, as me: UUID) async throws { throw AccountError.notConfigured }
    public func unfollow(_ id: UUID, as me: UUID) async throws { throw AccountError.notConfigured }
    public func blockedPeople() async throws -> [PersonRecord] { throw AccountError.notConfigured }
    public func block(_ id: UUID, as me: UUID) async throws { throw AccountError.notConfigured }
    public func unblock(_ id: UUID, as me: UUID) async throws { throw AccountError.notConfigured }
    public func sharing(of me: UUID) async throws -> SharingChoice { throw AccountError.notConfigured }
    public func setSharing(_ choice: SharingChoice, applyToExisting: Bool) async throws -> Int { throw AccountError.notConfigured }
    public func privacy(of me: UUID) async throws -> PrivacySettings { throw AccountError.notConfigured }
    public func setPrivacy(_ settings: PrivacySettings, as me: UUID) async throws { throw AccountError.notConfigured }
    public func feed(after cursor: FeedCursor?, pageSize: Int) async throws -> [FeedItem] { throw AccountError.notConfigured }
    public func photos(for checkIns: [UUID]) async throws -> [FeedPhoto] { throw AccountError.notConfigured }
    public func personCheckIns(of person: UUID, after cursor: FeedCursor?, pageSize: Int) async throws -> [FeedItem] { throw AccountError.notConfigured }
    public func airportCheckIns(at airport: Int, after cursor: FeedCursor?, pageSize: Int) async throws -> [FeedItem] { throw AccountError.notConfigured }
    public func airportActivity(at airport: Int) async throws -> AirportActivity { throw AccountError.notConfigured }
    public func activeAirports(days: Int, limit: Int) async throws -> [ActiveAirport] { throw AccountError.notConfigured }
    public func typeCheckIns(of type: String, after cursor: FeedCursor?, pageSize: Int) async throws -> [FeedItem] { throw AccountError.notConfigured }
    public func typeActivity(of type: String) async throws -> TypeActivity { throw AccountError.notConfigured }
    public func setSalute(_ on: Bool, checkIn: UUID, as me: UUID) async throws { throw AccountError.notConfigured }
    public func comments(checkIn: UUID) async throws -> [CheckInComment] { throw AccountError.notConfigured }
    public func addComment(_ body: String, checkIn: UUID, as me: UUID) async throws -> CheckInComment { throw AccountError.notConfigured }
    public func deleteComment(_ id: UUID) async throws { throw AccountError.notConfigured }
    public func report(_ kind: ReportKind, target: UUID, reason: String) async throws -> ReportOutcome { throw AccountError.notConfigured }
}
