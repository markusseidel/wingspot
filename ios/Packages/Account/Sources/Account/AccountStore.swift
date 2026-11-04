import Foundation
import Observation

public enum AccountError: Error, Equatable, Sendable {
    case invalidEmail
    case invalidUsername
    case usernameTaken
    /// The sign-in link was used already, has expired, or was requested on another device.
    case invalidLink
    case tooManyRequests
    case offline
    /// This build has no backend key, see ios/Config/Wingspot.xcconfig.
    case notConfigured
    case unknown
}

/// What the app needs from the backend. Lets tests run without a network.
public protocol AccountBackend: Sendable {
    /// The user with a session stored on this device. Doesn't need a network.
    func currentUserID() async -> UUID?
    func sendSignInLink(email: String, language: String?) async throws
    /// Finishes sign-in from the link in the email and returns the user's ID.
    func completeSignIn(from url: URL) async throws -> UUID
    func loadProfile(id: UUID) async throws -> Profile
    func saveProfile(_ profile: Profile) async throws
    func signOut() async throws
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
            state = .signedOut
            return
        }
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
            state = .signedIn(nil)
            await loadProfile(id: id)
        } catch {
            linkError = error as? AccountError ?? .unknown
        }
        return true
    }

    public func save(_ profile: Profile) async throws {
        guard Username.isValid(profile.username) else { throw AccountError.invalidUsername }
        try await backend.saveProfile(profile)
        state = .signedIn(profile)
    }

    /// Local check-ins stay on the device.
    public func signOut() async throws {
        try await backend.signOut()
        state = .signedOut
    }

    private func loadProfile(id: UUID) async {
        do {
            state = .signedIn(try await backend.loadProfile(id: id))
        } catch {
            // The client removes a session the server rejected. Anything else, such as being offline,
            // leaves the user signed in.
            if await backend.currentUserID() == nil {
                state = .signedOut
            }
        }
    }
}

/// For builds without a backend key. The app still works, except for signing in.
public struct UnconfiguredAccountBackend: AccountBackend {
    public init() {}

    public func currentUserID() async -> UUID? { nil }
    public func sendSignInLink(email: String, language: String?) async throws { throw AccountError.notConfigured }
    public func completeSignIn(from url: URL) async throws -> UUID { throw AccountError.notConfigured }
    public func loadProfile(id: UUID) async throws -> Profile { throw AccountError.notConfigured }
    public func saveProfile(_ profile: Profile) async throws { throw AccountError.notConfigured }
    public func signOut() async throws { throw AccountError.notConfigured }
}
