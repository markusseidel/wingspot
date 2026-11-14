import Foundation
import Observation

/// Who may see a check-in. The choice an account makes for its check-ins (`profiles.default_visibility`).
public enum SharingChoice: String, CaseIterable, Sendable {
    case `private`
    case friends
    case followers
    case `public`
}

/// Someone else's public profile, with how they relate to the signed-in user.
public struct Person: Equatable, Sendable, Identifiable {
    public let id: UUID
    public var username: String
    public var displayName: String?
    public var isPrivate: Bool
    /// The signed-in user follows them.
    public var isFollowing: Bool
    /// They follow the signed-in user.
    public var followsYou: Bool

    public init(
        id: UUID, username: String, displayName: String? = nil, isPrivate: Bool = false,
        isFollowing: Bool = false, followsYou: Bool = false
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.isPrivate = isPrivate
        self.isFollowing = isFollowing
        self.followsYou = followsYou
    }

    /// Each follows the other.
    public var isFriend: Bool { isFollowing && followsYou }
}

/// A person as the database returns it, before the relation to the signed-in user is added.
public struct PersonRecord: Equatable, Sendable {
    public let id: UUID
    public let username: String
    public let displayName: String?
    public let isPrivate: Bool

    public init(id: UUID, username: String, displayName: String?, isPrivate: Bool) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.isPrivate = isPrivate
    }
}

/// What the social screens need from the backend. Lets tests run without a network.
/// Who can see the account, apart from the sharing choice of each check-in.
public struct PrivacySettings: Equatable, Sendable {
    /// A private profile shows its details and check-ins only to friends.
    public var isPrivate: Bool
    /// Public check-ins reach strangers only after this many minutes. Friends see them at once.
    public var postDelayMinutes: Int

    /// What the app offers. The database accepts anything from 0 to 1440.
    public static let delayChoices = [0, 60, 360, 1440]

    public init(isPrivate: Bool = false, postDelayMinutes: Int = 0) {
        self.isPrivate = isPrivate
        self.postDelayMinutes = postDelayMinutes
    }
}

public protocol SocialBackend: Sendable {
    /// Profiles whose username contains `text`, without `me`, by username.
    func searchPeople(_ text: String, excluding me: UUID, limit: Int) async throws -> [PersonRecord]
    /// People the user follows, and people who follow the user. Only the ones among `ids`.
    func relationships(of me: UUID, among ids: [UUID]) async throws -> (following: Set<UUID>, followers: Set<UUID>)
    func followingIDs(of me: UUID) async throws -> [UUID]
    func followerIDs(of me: UUID) async throws -> [UUID]
    func profiles(ids: [UUID]) async throws -> [PersonRecord]
    func follow(_ id: UUID, as me: UUID) async throws
    func unfollow(_ id: UUID, as me: UUID) async throws
    func blockedPeople() async throws -> [PersonRecord]
    func block(_ id: UUID, as me: UUID) async throws
    func unblock(_ id: UUID, as me: UUID) async throws
    func sharing(of me: UUID) async throws -> SharingChoice
    /// Returns how many earlier check-ins changed.
    func setSharing(_ choice: SharingChoice, applyToExisting: Bool) async throws -> Int
    func privacy(of me: UUID) async throws -> PrivacySettings
    func setPrivacy(_ settings: PrivacySettings, as me: UUID) async throws
}

/// Finding people, following, blocking and the sharing choice. Everything here needs a network.
@MainActor
@Observable
public final class SocialStore {
    private let backend: SocialBackend
    private let userID: @MainActor () -> UUID?

    /// - Parameter userID: the signed-in user, or `nil`.
    public init(backend: SocialBackend, userID: @escaping @MainActor () -> UUID?) {
        self.backend = backend
        self.userID = userID
    }

    private func me() throws -> UUID {
        guard let id = userID() else { throw AccountError.unknown }
        return id
    }

    /// Searches usernames. Typed text is cut down to what a username can hold, so it can't act as a filter pattern.
    public func search(_ text: String) async throws -> [Person] {
        let query = String(Username.normalized(text).filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") })
        guard query.count >= 2 else { return [] }
        let me = try me()
        let records = try await backend.searchPeople(query, excluding: me, limit: 20)
        return try await people(records, me: me)
    }

    public func following() async throws -> [Person] {
        let me = try me()
        let ids = try await backend.followingIDs(of: me)
        return try await people(try await backend.profiles(ids: ids), me: me)
    }

    public func followers() async throws -> [Person] {
        let me = try me()
        let ids = try await backend.followerIDs(of: me)
        return try await people(try await backend.profiles(ids: ids), me: me)
    }

    /// The people the user blocked. Blocking hides the two from each other, so they have no relation left.
    public func blocked() async throws -> [Person] {
        try await backend.blockedPeople().map {
            Person(id: $0.id, username: $0.username, displayName: $0.displayName, isPrivate: $0.isPrivate)
        }
    }

    /// Looks up one person again, for example to show them after following.
    public func person(_ id: UUID) async throws -> Person? {
        let me = try me()
        guard let record = try await backend.profiles(ids: [id]).first else { return nil }
        return try await people([record], me: me).first
    }

    /// Told after a follow worked, so the app can offer notifications at a good moment.
    @ObservationIgnored public var onFollowed: (@MainActor () -> Void)?

    public func follow(_ id: UUID) async throws {
        try await backend.follow(id, as: try me())
        onFollowed?()
    }

    public func unfollow(_ id: UUID) async throws {
        try await backend.unfollow(id, as: try me())
    }

    public func block(_ id: UUID) async throws {
        try await backend.block(id, as: try me())
    }

    public func unblock(_ id: UUID) async throws {
        try await backend.unblock(id, as: try me())
    }

    public func sharing() async throws -> SharingChoice {
        try await backend.sharing(of: try me())
    }

    @discardableResult
    public func setSharing(_ choice: SharingChoice, applyToExisting: Bool) async throws -> Int {
        try await backend.setSharing(choice, applyToExisting: applyToExisting)
    }

    public func privacy() async throws -> PrivacySettings {
        try await backend.privacy(of: try me())
    }

    public func setPrivacy(_ settings: PrivacySettings) async throws {
        try await backend.setPrivacy(settings, as: try me())
    }

    private func people(_ records: [PersonRecord], me: UUID) async throws -> [Person] {
        guard !records.isEmpty else { return [] }
        let relations = try await backend.relationships(of: me, among: records.map(\.id))
        return records.map {
            Person(
                id: $0.id, username: $0.username, displayName: $0.displayName, isPrivate: $0.isPrivate,
                isFollowing: relations.following.contains($0.id), followsYou: relations.followers.contains($0.id)
            )
        }
    }
}
