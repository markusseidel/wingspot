import Foundation
import SwiftData

/// The highest level of a badge that was shown to this user as a celebration.
@Model
public final class BadgeAck {
    /// `<user id>|<badge id>`, so every account on this iPhone has its own.
    @Attribute(.unique) public var key: String
    public var userID: UUID
    public var badgeID: String
    public var level: Int

    public init(userID: UUID, badgeID: String, level: Int) {
        self.key = Self.key(userID: userID, badgeID: badgeID)
        self.userID = userID
        self.badgeID = badgeID
        self.level = level
    }

    static func key(userID: UUID, badgeID: String) -> String { "\(userID.uuidString)|\(badgeID)" }
}

/// What this iPhone knows about an account's badges.
@Model
public final class BadgeAccount {
    @Attribute(.unique) public var userID: UUID
    /// When this account first appeared on this iPhone. Badges unlocked before then, such as after a reinstall,
    /// are not celebrated again.
    public var firstSeenAt: Date
    /// The last answer of `GET /v1/me/progress`, as the server sent it, for offline use.
    public var cachedProgress: Data?
    public var cachedAt: Date?

    public init(userID: UUID, firstSeenAt: Date) {
        self.userID = userID
        self.firstSeenAt = firstSeenAt
    }
}
