import Foundation
import Observation

/// The "What's new" text of one build of the app. German is optional; English is always there.
public struct ReleaseNote: Hashable, Sendable, Identifiable, Codable {
    public let id: UUID
    public let version: String
    public let build: Int64
    /// `beta` or `release`.
    public let kind: String
    public let titleEN: String
    public let bodyEN: String
    public let titleDE: String?
    public let bodyDE: String?
    public let releasedAt: Date

    public init(id: UUID = UUID(), version: String, build: Int64, kind: String = "beta", titleEN: String, bodyEN: String,
                titleDE: String? = nil, bodyDE: String? = nil, releasedAt: Date = Date()) {
        self.id = id
        self.version = version
        self.build = build
        self.kind = kind
        self.titleEN = titleEN
        self.bodyEN = bodyEN
        self.titleDE = titleDE
        self.bodyDE = bodyDE
        self.releasedAt = releasedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, version, build, kind
        case titleEN = "title_en"
        case bodyEN = "body_en"
        case titleDE = "title_de"
        case bodyDE = "body_de"
        case releasedAt = "released_at"
    }

    public var isBeta: Bool { kind == "beta" }

    /// The title and text in `language` (`de` or anything else), English when there is no translation.
    public func text(language: String) -> (title: String, lines: [String]) {
        if language == "de", let title = titleDE, !title.isEmpty, let body = bodyDE, !body.isEmpty { return (title, Self.lines(of: body)) }
        return (titleEN, Self.lines(of: bodyEN))
    }

    /// The text as lines, without the leading "- " of a bullet. Empty lines are dropped.
    public static func lines(of body: String) -> [String] {
        body.split(whereSeparator: \.isNewline).map { line in
            var text = line.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("- ") { text = String(text.dropFirst(2)) }
            return text
        }.filter { !$0.isEmpty }
    }
}

public protocol ReleaseNotesBackend: Sendable {
    /// `get_release_notes`. Works signed out too.
    func releaseNotes(platform: String) async throws -> [ReleaseNote]
}

/// What's new, for this iPhone's builds. What the server sent last time is kept on the phone, so the screen opens offline.
@MainActor
@Observable
public final class ReleaseNotesStore {
    private static let cacheKey = "releaseNotes"

    public private(set) var notes: [ReleaseNote]
    public private(set) var isLoading = false
    /// True when the last request failed; the notes shown are then the ones kept from before.
    public private(set) var loadFailed = false

    private let backend: ReleaseNotesBackend
    @ObservationIgnored private let defaults: UserDefaults

    public init(backend: ReleaseNotesBackend, defaults: UserDefaults = .standard) {
        self.backend = backend
        self.defaults = defaults
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        notes = defaults.data(forKey: Self.cacheKey).flatMap { try? decoder.decode([ReleaseNote].self, from: $0) } ?? []
    }

    /// Asks the server. A failed request leaves the kept list as it is.
    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fresh = try await backend.releaseNotes(platform: "ios")
            notes = fresh.sorted { $0.build > $1.build }
            loadFailed = false
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            defaults.set(try? encoder.encode(notes), forKey: Self.cacheKey)
        } catch {
            loadFailed = true
        }
    }

    /// Builds newer than the installed one: what the next update brings. Newest first.
    public func newer(than installed: Int64) -> [ReleaseNote] { notes.filter { $0.build > installed } }
    /// The installed build and the ones before it. Newest first.
    public func installedAndOlder(than installed: Int64) -> [ReleaseNote] { notes.filter { $0.build <= installed } }
}

extension UnconfiguredAccountBackend: ReleaseNotesBackend {
    public func releaseNotes(platform: String) async throws -> [ReleaseNote] { throw AccountError.notConfigured }
}
