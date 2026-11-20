import Foundation
import Supabase

/// What the board is ranked by.
public enum LeaderboardMetric: String, CaseIterable, Sendable {
    case distance, flights, countries, airports
}

/// This calendar year, or all time.
public enum LeaderboardPeriod: String, CaseIterable, Sendable {
    case year, all
}

/// One place on the board.
public struct LeaderboardRow: Identifiable, Equatable, Sendable, Decodable {
    public let userID: UUID
    public let username: String
    public let displayName: String?
    public let value: Int
    public let isMe: Bool
    public var id: UUID { userID }

    public init(userID: UUID, username: String, displayName: String?, value: Int, isMe: Bool) {
        self.userID = userID
        self.username = username
        self.displayName = displayName
        self.value = value
        self.isMe = isMe
    }

    /// The name to show.
    public var name: String {
        if let displayName, !displayName.trimmingCharacters(in: .whitespaces).isEmpty { return displayName }
        return username
    }

    private enum CodingKeys: String, CodingKey {
        case username, value
        case userID = "user_id"
        case displayName = "display_name"
        case isMe = "is_me"
    }
}

/// The friends leaderboard, and whether you are on other people's boards.
public protocol LeaderboardBackend: Sendable {
    func leaderboard(metric: LeaderboardMetric, period: LeaderboardPeriod) async throws -> [LeaderboardRow]
    func showsOnLeaderboard(of me: UUID) async throws -> Bool
    func setShowsOnLeaderboard(_ shown: Bool, as me: UUID) async throws
}

extension SupabaseAccountBackend: LeaderboardBackend {
    public func leaderboard(metric: LeaderboardMetric, period: LeaderboardPeriod) async throws -> [LeaderboardRow] {
        try await mappingErrors {
            try await client.rpc("get_leaderboard", params: ["p_metric": metric.rawValue, "p_period": period.rawValue]).execute().value
        }
    }

    public func showsOnLeaderboard(of me: UUID) async throws -> Bool {
        let row: ShowRow = try await mappingErrors {
            try await client.from("profiles").select("show_on_leaderboard").eq("id", value: me).single().execute().value
        }
        return row.shown
    }

    public func setShowsOnLeaderboard(_ shown: Bool, as me: UUID) async throws {
        try await mappingErrors {
            _ = try await client.from("profiles").update(ShowUpdate(shown: shown), returning: .minimal).eq("id", value: me).execute()
        }
    }
}

private struct ShowRow: Decodable {
    let shown: Bool
    private enum CodingKeys: String, CodingKey { case shown = "show_on_leaderboard" }
}

private struct ShowUpdate: Encodable {
    let shown: Bool
    private enum CodingKeys: String, CodingKey { case shown = "show_on_leaderboard" }
}

extension UnconfiguredAccountBackend: LeaderboardBackend {
    public func leaderboard(metric: LeaderboardMetric, period: LeaderboardPeriod) async throws -> [LeaderboardRow] { throw AccountError.notConfigured }
    public func showsOnLeaderboard(of me: UUID) async throws -> Bool { throw AccountError.notConfigured }
    public func setShowsOnLeaderboard(_ shown: Bool, as me: UUID) async throws { throw AccountError.notConfigured }
}
