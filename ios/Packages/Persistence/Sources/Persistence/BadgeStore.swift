import Foundation
import Observation
import SwiftData
import WingspotCore

/// Fetches the signed-in user's progress. Tests replace it.
public protocol ProgressSource: Sendable {
    func progress() async throws -> (progress: UserProgress, raw: Data)
}

/// A badge level to celebrate.
public struct Celebration: Equatable, Identifiable, Sendable {
    public let badge: BadgeProgress
    /// The level that was shown before, 0 for a new badge.
    public let previousLevel: Int
    public var id: String { "\(badge.id)#\(badge.level)" }
}

/// XP, level and badges, and what still has to be celebrated.
///
/// The server decides what is unlocked. This store celebrates the difference between that and what it has
/// already shown, so a lost upload answer, an unlock on another device, or an app that closed too early never
/// loses a celebration. Badges unlocked before the account first appeared on this iPhone are recorded without
/// celebration.
@MainActor
@Observable
public final class BadgeStore {
    /// Unlocks within this long before the account appeared still count as new, so a slightly wrong clock
    /// can't swallow the first celebration.
    static let clockMargin: TimeInterval = 5 * 60

    public private(set) var progress: UserProgress?
    public private(set) var celebrations: [Celebration] = []
    /// True when the last refresh failed. The last known progress stays.
    public private(set) var refreshFailed = false

    private let context: ModelContext
    private let source: ProgressSource
    private let now: () -> Date
    private var userID: UUID?

    public init(context: ModelContext, source: ProgressSource, now: @escaping () -> Date = Date.init) {
        self.context = context
        self.source = source
        self.now = now
    }

    /// Call when the signed-in user changes, including at launch. Shows the last known progress right away.
    public func begin(userID: UUID?) {
        guard userID != self.userID else { return }
        self.userID = userID
        celebrations = []
        refreshFailed = false
        progress = nil
        guard let userID else { return }
        let account = account(for: userID)
        if let data = account.cachedProgress { progress = try? UserProgress.decode(data) }
    }

    /// Asks the server and works out what to celebrate. Does nothing when signed out.
    public func refresh() async {
        guard let user = userID else { return }
        do {
            let (fresh, raw) = try await source.progress()
            guard user == userID else { return }  // another account signed in meanwhile
            apply(fresh, raw: raw, for: user)
            refreshFailed = false
        } catch {
            refreshFailed = true
        }
    }

    /// The user has seen the celebrations.
    public func acknowledge() {
        guard let user = userID else { return }
        for celebration in celebrations { setAck(celebration.badge.level, badge: celebration.badge.id, user: user) }
        try? context.save()
        celebrations = []
    }

    private func apply(_ fresh: UserProgress, raw: Data, for user: UUID) {
        let account = account(for: user)
        let cutoff = account.firstSeenAt.addingTimeInterval(-Self.clockMargin)
        var pending: [Celebration] = []
        for badge in fresh.badges where badge.level > 0 {
            let seen = ack(badge.id, user: user)
            guard badge.level > seen else { continue }
            if let unlockedAt = badge.unlockedAt, unlockedAt >= cutoff {
                pending.append(Celebration(badge: badge, previousLevel: seen))
            } else {
                // Unlocked before this account appeared here: remember it, don't celebrate it.
                setAck(badge.level, badge: badge.id, user: user)
            }
        }
        account.cachedProgress = raw
        account.cachedAt = now()
        try? context.save()
        progress = fresh
        celebrations = pending
    }

    private func account(for user: UUID) -> BadgeAccount {
        let descriptor = FetchDescriptor<BadgeAccount>(predicate: #Predicate { $0.userID == user })
        if let existing = try? context.fetch(descriptor).first { return existing }
        let created = BadgeAccount(userID: user, firstSeenAt: now())
        context.insert(created)
        try? context.save()
        return created
    }

    private func ack(_ badge: String, user: UUID) -> Int {
        let key = BadgeAck.key(userID: user, badgeID: badge)
        let descriptor = FetchDescriptor<BadgeAck>(predicate: #Predicate { $0.key == key })
        return (try? context.fetch(descriptor).first)?.level ?? 0
    }

    private func setAck(_ level: Int, badge: String, user: UUID) {
        let key = BadgeAck.key(userID: user, badgeID: badge)
        let descriptor = FetchDescriptor<BadgeAck>(predicate: #Predicate { $0.key == key })
        if let existing = try? context.fetch(descriptor).first {
            existing.level = max(existing.level, level)
        } else {
            context.insert(BadgeAck(userID: user, badgeID: badge, level: level))
        }
    }
}
