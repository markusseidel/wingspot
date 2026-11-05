import Foundation

/// Text by language code, such as `{"en": "Wheels Up", "de": "Abheben"}`. English is always there.
public struct LocalizedText: Decodable, Equatable, Sendable {
    public let values: [String: String]

    public init(_ values: [String: String]) {
        self.values = values
    }

    public init(from decoder: Decoder) throws {
        values = try decoder.singleValueContainer().decode([String: String].self)
    }

    /// The first of `languages` that has a text, then English, then whatever there is.
    public func resolved(preferring languages: [String]) -> String {
        for language in languages {
            // "de-DE" and "de_AT" both count as "de".
            let code = language.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? language
            if let text = values[code] { return text }
        }
        return values["en"] ?? values.values.sorted().first ?? ""
    }
}

/// One badge in `GET /v1/me/progress` (`BadgeProgress` in contracts/openapi.yaml).
public struct BadgeProgress: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: LocalizedText
    public let description: LocalizedText?
    /// An open set: `milestones`, `airports`, `countries`, `types`, `time`, `hidden`, and maybe more later.
    public let category: String
    public let isHidden: Bool
    /// The value needed for each level, ascending. One entry for a single badge.
    public let levels: [Int]
    /// The current value of the badge's metric.
    public let value: Int
    /// The highest level unlocked, 0 if none. It never goes down.
    public let level: Int
    /// When the latest level was unlocked.
    public let unlockedAt: Date?

    public init(
        id: String, name: LocalizedText, description: LocalizedText? = nil, category: String, isHidden: Bool = false,
        levels: [Int], value: Int, level: Int, unlockedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.isHidden = isHidden
        self.levels = levels
        self.value = value
        self.level = level
        self.unlockedAt = unlockedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, category
        case isHidden = "hidden"
        case levels, value, level
        case unlockedAt = "unlocked_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(LocalizedText.self, forKey: .name)
        description = try container.decodeIfPresent(LocalizedText.self, forKey: .description)
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? ""
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        levels = try container.decode([Int].self, forKey: .levels)
        value = try container.decode(Int.self, forKey: .value)
        level = try container.decode(Int.self, forKey: .level)
        unlockedAt = try container.decodeIfPresent(String.self, forKey: .unlockedAt).flatMap(Self.parseDate)
    }

    /// Postgres sends microseconds and a numeric offset, for example `2026-11-05T20:31:20.920684+00:00`.
    private static func parseDate(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }

    public var isSingle: Bool { levels.count <= 1 }
    public var isComplete: Bool { level >= levels.count }
    /// The value for the next level, or `nil` once every level is unlocked.
    public var nextTarget: Int? { level < levels.count ? levels[level] : nil }
}

/// The answer of `GET /v1/me/progress` (`Progress` in contracts/openapi.yaml).
public struct UserProgress: Decodable, Equatable, Sendable {
    public let xp: Int
    public let level: Int
    /// The XP at which the current level starts.
    public let xpForLevel: Int
    public let xpForNextLevel: Int
    public let badges: [BadgeProgress]
    /// How many hidden badges are still locked.
    public let hiddenRemaining: Int

    public init(xp: Int, level: Int, xpForLevel: Int, xpForNextLevel: Int, badges: [BadgeProgress], hiddenRemaining: Int) {
        self.xp = xp
        self.level = level
        self.xpForLevel = xpForLevel
        self.xpForNextLevel = xpForNextLevel
        self.badges = badges
        self.hiddenRemaining = hiddenRemaining
    }

    private enum CodingKeys: String, CodingKey {
        case xp, level, badges
        case xpForLevel = "xp_for_level"
        case xpForNextLevel = "xp_for_next_level"
        case hiddenRemaining = "hidden_remaining"
    }

    /// 0 at the start of the level, 1 when the next level is reached.
    public var levelFraction: Double {
        let span = xpForNextLevel - xpForLevel
        return span > 0 ? min(1, max(0, Double(xp - xpForLevel) / Double(span))) : 0
    }

    /// Decodes an answer as the server sends it, which is also how the app keeps it between launches.
    public static func decode(_ data: Data) throws -> UserProgress {
        try JSONDecoder().decode(UserProgress.self, from: data)
    }
}

/// Rank titles by level (concept §5.3). The app translates the names.
public enum Rank: Int, CaseIterable, Sendable {
    case cadet, studentPilot, firstOfficer, captain, seniorCaptain, chiefPilot, ace, legend

    public init(level: Int) {
        switch level {
        case ..<5: self = .cadet
        case 5..<10: self = .studentPilot
        case 10..<15: self = .firstOfficer
        case 15..<20: self = .captain
        case 20..<25: self = .seniorCaptain
        case 25..<30: self = .chiefPilot
        case 30..<35: self = .ace
        default: self = .legend
        }
    }
}
