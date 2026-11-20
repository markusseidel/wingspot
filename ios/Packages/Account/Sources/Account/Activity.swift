import Foundation
import Supabase

/// One row of the activity inbox, as `get_notifications` returns it.
public struct ActivityItem: Identifiable, Hashable, Sendable, Decodable {
    public let id: UUID
    /// What happened: follow, salute, comment, checkin, tagged, and the kinds later features add.
    public let kind: String
    public let actorID: UUID
    public let username: String
    public let displayName: String?
    /// The check-in it is about, if the person may still see it.
    public let checkInID: UUID?
    /// The route, airport or registration of that check-in.
    public let subject: String?
    public let snippet: String?
    public let createdAt: Date
    public var isRead: Bool

    private enum CodingKeys: String, CodingKey {
        case id, kind, username, subject, snippet
        case actorID = "actor_id"
        case displayName = "display_name"
        case checkInID = "checkin_id"
        case createdAt = "created_at"
        case isRead = "is_read"
    }

    public init(
        id: UUID, kind: String, actorID: UUID, username: String, displayName: String?, checkInID: UUID?,
        subject: String?, snippet: String?, createdAt: Date, isRead: Bool
    ) {
        self.id = id
        self.kind = kind
        self.actorID = actorID
        self.username = username
        self.displayName = displayName
        self.checkInID = checkInID
        self.subject = subject
        self.snippet = snippet
        self.createdAt = createdAt
        self.isRead = isRead
    }

    /// The name to show for who did it.
    public var who: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return username
    }
}

/// The activity inbox: what happened around you, newest first.
public protocol ActivityBackend: Sendable {
    func activity(before: Date?, limit: Int) async throws -> [ActivityItem]
    /// How many are unread, up to 99.
    func unreadActivityCount() async throws -> Int
    func markActivityRead() async throws
}

extension SupabaseAccountBackend: ActivityBackend {
    public func activity(before: Date?, limit: Int) async throws -> [ActivityItem] {
        try await mappingErrors {
            try await client.rpc("get_notifications", params: ActivityParams(before: before, limit: limit)).execute().value
        }
    }

    public func unreadActivityCount() async throws -> Int {
        try await mappingErrors { try await client.rpc("unread_notification_count").execute().value }
    }

    public func markActivityRead() async throws {
        try await mappingErrors { _ = try await client.rpc("mark_notifications_read").execute() }
    }
}

private struct ActivityParams: Encodable {
    let before: Date?
    let limit: Int

    private enum CodingKeys: String, CodingKey { case before, lim }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(before, forKey: .before)
        try container.encode(limit, forKey: .lim)
    }
}

extension UnconfiguredAccountBackend: ActivityBackend {
    public func activity(before: Date?, limit: Int) async throws -> [ActivityItem] { throw AccountError.notConfigured }
    public func unreadActivityCount() async throws -> Int { throw AccountError.notConfigured }
    public func markActivityRead() async throws { throw AccountError.notConfigured }
}
