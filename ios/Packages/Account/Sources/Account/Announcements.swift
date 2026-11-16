import Foundation
import Observation

/// A short message from the project owner, shown at the top of the Feed. German is optional; English is always there.
public struct Announcement: Hashable, Sendable, Identifiable, Codable {
    public let id: UUID
    public let titleEN: String
    public let bodyEN: String
    public let titleDE: String?
    public let bodyDE: String?

    public init(id: UUID, titleEN: String, bodyEN: String, titleDE: String? = nil, bodyDE: String? = nil) {
        self.id = id
        self.titleEN = titleEN
        self.bodyEN = bodyEN
        self.titleDE = titleDE
        self.bodyDE = bodyDE
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case titleEN = "title_en"
        case bodyEN = "body_en"
        case titleDE = "title_de"
        case bodyDE = "body_de"
    }

    /// The title and text in `language` (`de` or anything else), English when there is no translation.
    public func text(language: String) -> (title: String, body: String) {
        if language == "de", let title = titleDE, !title.isEmpty, let body = bodyDE, !body.isEmpty { return (title, body) }
        return (titleEN, bodyEN)
    }
}

public protocol AnnouncementBackend: Sendable {
    /// `get_announcements`. Works signed out too.
    func announcements() async throws -> [Announcement]
}

/// The announcements at the top of the Feed. What the server sent last time is kept on the phone, so the card shows
/// offline; a dismissal is remembered by id.
@MainActor
@Observable
public final class AnnouncementStore {
    private static let cacheKey = "announcements"
    private static let dismissedKey = "announcementsDismissed"

    private var all: [Announcement]
    private var dismissed: Set<UUID>

    private let backend: AnnouncementBackend
    @ObservationIgnored private let defaults: UserDefaults

    public init(backend: AnnouncementBackend, defaults: UserDefaults = .standard) {
        self.backend = backend
        self.defaults = defaults
        all = defaults.data(forKey: Self.cacheKey).flatMap { try? JSONDecoder().decode([Announcement].self, from: $0) } ?? []
        dismissed = Set((defaults.stringArray(forKey: Self.dismissedKey) ?? []).compactMap(UUID.init(uuidString:)))
    }

    /// What to show: the announcements that weren't dismissed, newest first.
    public var visible: [Announcement] { all.filter { !dismissed.contains($0.id) } }

    /// Asks the server. A failed request leaves what is shown as it is.
    public func refresh() async {
        guard let fresh = try? await backend.announcements() else { return }
        all = fresh
        defaults.set(try? JSONEncoder().encode(fresh), forKey: Self.cacheKey)
        // Forget dismissals of announcements that are gone, so the list of ids doesn't grow for ever.
        dismissed = dismissed.intersection(fresh.map(\.id))
        saveDismissed()
    }

    public func dismiss(_ id: UUID) {
        dismissed.insert(id)
        saveDismissed()
    }

    private func saveDismissed() {
        defaults.set(dismissed.map(\.uuidString).sorted(), forKey: Self.dismissedKey)
    }
}

extension UnconfiguredAccountBackend: AnnouncementBackend {
    public func announcements() async throws -> [Announcement] { throw AccountError.notConfigured }
}
