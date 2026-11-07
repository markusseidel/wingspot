import Foundation
import Observation

/// One check-in in the feed, as `get_feed` returns it.
public struct FeedItem: Hashable, Sendable, Identifiable, Decodable {
    public let id: UUID
    public let userID: UUID
    public let username: String
    public let displayName: String?
    /// `spotted`, `flown` or `airport`. An open set, so newer kinds still show.
    public let kind: String
    public let occurredAt: Date
    /// The time exactly as the server sent it. Paging sends it back unchanged, because rounding it would skip or repeat rows.
    public let cursorTime: String
    public let registration: String?
    public let typeICAO: String?
    public let typeName: String?
    public let airportCode: String?
    public let originCode: String?
    public let destinationCode: String?
    public let flightNumber: String?
    public let distanceKm: Int?
    public let salutes: Int
    public let comments: Int
    public let saluted: Bool

    public init(
        id: UUID, userID: UUID, username: String, displayName: String? = nil, kind: String, occurredAt: Date,
        cursorTime: String? = nil, registration: String? = nil, typeICAO: String? = nil, typeName: String? = nil,
        airportCode: String? = nil, originCode: String? = nil, destinationCode: String? = nil,
        flightNumber: String? = nil, distanceKm: Int? = nil, salutes: Int = 0, comments: Int = 0, saluted: Bool = false
    ) {
        self.id = id
        self.userID = userID
        self.username = username
        self.displayName = displayName
        self.kind = kind
        self.occurredAt = occurredAt
        self.cursorTime = cursorTime ?? ISO8601DateFormatter().string(from: occurredAt)
        self.registration = registration
        self.typeICAO = typeICAO
        self.typeName = typeName
        self.airportCode = airportCode
        self.originCode = originCode
        self.destinationCode = destinationCode
        self.flightNumber = flightNumber
        self.distanceKm = distanceKm
        self.salutes = salutes
        self.comments = comments
        self.saluted = saluted
    }

    /// The same check-in with new counts, for updates that don't need another request.
    public func updating(salutes: Int? = nil, comments: Int? = nil, saluted: Bool? = nil) -> FeedItem {
        FeedItem(
            id: id, userID: userID, username: username, displayName: displayName, kind: kind, occurredAt: occurredAt,
            cursorTime: cursorTime, registration: registration, typeICAO: typeICAO, typeName: typeName,
            airportCode: airportCode, originCode: originCode, destinationCode: destinationCode,
            flightNumber: flightNumber, distanceKm: distanceKm, salutes: salutes ?? self.salutes,
            comments: comments ?? self.comments, saluted: saluted ?? self.saluted
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, username, kind, registration, salutes, comments, saluted
        case userID = "user_id"
        case displayName = "display_name"
        case occurredAt = "occurred_at"
        case typeICAO = "type_icao"
        case typeName = "type_name"
        case airportCode = "airport_code"
        case originCode = "origin_code"
        case destinationCode = "destination_code"
        case flightNumber = "flight_number"
        case distanceKm = "distance_km"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        userID = try c.decode(UUID.self, forKey: .userID)
        username = try c.decode(String.self, forKey: .username)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        kind = try c.decode(String.self, forKey: .kind)
        let time = try c.decode(String.self, forKey: .occurredAt)
        guard let date = Self.parse(time) else {
            throw DecodingError.dataCorruptedError(forKey: .occurredAt, in: c, debugDescription: "Not a date: \(time)")
        }
        occurredAt = date
        cursorTime = time
        registration = try c.decodeIfPresent(String.self, forKey: .registration)
        typeICAO = try c.decodeIfPresent(String.self, forKey: .typeICAO)
        typeName = try c.decodeIfPresent(String.self, forKey: .typeName)
        airportCode = try c.decodeIfPresent(String.self, forKey: .airportCode)
        originCode = try c.decodeIfPresent(String.self, forKey: .originCode)
        destinationCode = try c.decodeIfPresent(String.self, forKey: .destinationCode)
        flightNumber = try c.decodeIfPresent(String.self, forKey: .flightNumber)
        distanceKm = try c.decodeIfPresent(Int.self, forKey: .distanceKm)
        salutes = try c.decodeIfPresent(Int.self, forKey: .salutes) ?? 0
        comments = try c.decodeIfPresent(Int.self, forKey: .comments) ?? 0
        saluted = try c.decodeIfPresent(Bool.self, forKey: .saluted) ?? false
    }

    /// Postgres sends times with or without fractions of a second.
    static func parse(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? plain.date(from: text)
    }
}

/// Where the next page starts: the last item of the page before.
public struct FeedCursor: Equatable, Sendable {
    public let time: String
    public let id: UUID

    public init(time: String, id: UUID) {
        self.time = time
        self.id = id
    }
}

/// A photo on a check-in, with a link that works for a limited time.
public struct FeedPhoto: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let checkInID: UUID
    public let url: URL
    public let width: Int?
    public let height: Int?

    public init(id: UUID, checkInID: UUID, url: URL, width: Int? = nil, height: Int? = nil) {
        self.id = id
        self.checkInID = checkInID
        self.url = url
        self.width = width
        self.height = height
    }
}

public protocol FeedBackend: Sendable {
    func feed(after cursor: FeedCursor?, pageSize: Int) async throws -> [FeedItem]
    /// The photos of these check-ins that the caller may see, in order, with signed links.
    func photos(for checkIns: [UUID]) async throws -> [FeedPhoto]
}

/// The Feed tab's data: your check-ins and those of people you follow, newest first, in pages.
@MainActor
@Observable
public final class FeedStore {
    public static let pageSize = 30

    public private(set) var items: [FeedItem] = []
    public private(set) var isLoading = false
    /// The last page was short, so there is nothing older.
    public private(set) var reachedEnd = false
    public private(set) var failure: AccountError?
    /// True once a first page was loaded, so an empty feed isn't shown while it is still loading.
    public private(set) var hasLoaded = false
    /// The photos of the check-ins in `items`. A card shows its photos once they arrive.
    public private(set) var photos: [UUID: [FeedPhoto]] = [:]

    private let backend: FeedBackend
    private let reactions: ReactionBackend
    private let userID: @MainActor () -> UUID?
    /// Changes whenever the list restarts, so an answer to an older request is dropped.
    private var generation = 0

    public init(backend: FeedBackend, reactions: ReactionBackend, userID: @escaping @MainActor () -> UUID?) {
        self.backend = backend
        self.reactions = reactions
        self.userID = userID
    }

    /// Salutes or un-salutes a check-in. The card changes at once, and goes back if the request fails.
    public func toggleSalute(_ id: UUID) async {
        guard let me = userID(), let index = items.firstIndex(where: { $0.id == id }) else { return }
        let before = items[index]
        let on = !before.saluted
        items[index] = before.updating(salutes: max(0, before.salutes + (on ? 1 : -1)), saluted: on)
        do {
            try await reactions.setSalute(on, checkIn: id, as: me)
            failure = nil
        } catch {
            if let now = items.firstIndex(where: { $0.id == id }) { items[now] = items[now].updating(salutes: before.salutes, saluted: before.saluted) }
            failure = (error as? AccountError) ?? .unknown
        }
    }

    /// The comments of one check-in. Its count is kept in step with the card.
    public func commentStore(for id: UUID) -> CheckInCommentStore {
        CheckInCommentStore(
            checkIn: id, backend: reactions, userID: userID,
            onCountChange: { [weak self] count in self?.setCommentCount(count, for: id) }
        )
    }

    /// Keeps a card's comment count in step with the comments screen.
    public func setCommentCount(_ count: Int, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].comments != count else { return }
        items[index] = items[index].updating(comments: count)
    }

    /// Loads the newest page and replaces the list. Keeps the old list when it fails.
    public func refresh() async {
        generation += 1
        let mine = generation
        isLoading = true
        defer { if mine == generation { isLoading = false } }
        do {
            let page = try await backend.feed(after: nil, pageSize: Self.pageSize)
            guard mine == generation else { return }
            items = Self.unique(page)
            reachedEnd = page.count < Self.pageSize
            failure = nil
            hasLoaded = true
            photos = [:]
            await loadPhotos(for: items.map(\.id), generation: mine)
        } catch {
            guard mine == generation else { return }
            failure = (error as? AccountError) ?? .unknown
        }
    }

    /// Loads the next older page. Does nothing while loading, at the end, or before the first page.
    public func loadMore() async {
        guard hasLoaded, !isLoading, !reachedEnd, let last = items.last else { return }
        let mine = generation
        isLoading = true
        defer { if mine == generation { isLoading = false } }
        do {
            let page = try await backend.feed(after: FeedCursor(time: last.cursorTime, id: last.id), pageSize: Self.pageSize)
            guard mine == generation else { return }
            let known = Set(items.map(\.id))
            let added = Self.unique(page).filter { !known.contains($0.id) }
            items += added
            reachedEnd = page.count < Self.pageSize
            failure = nil
            await loadPhotos(for: added.map(\.id), generation: mine)
        } catch {
            guard mine == generation else { return }
            failure = (error as? AccountError) ?? .unknown
        }
    }

    /// Photos are a bonus: if they can't be loaded, the cards stay as they are.
    private func loadPhotos(for ids: [UUID], generation mine: Int) async {
        guard !ids.isEmpty, let found = try? await backend.photos(for: ids), mine == generation else { return }
        for (id, group) in Dictionary(grouping: found, by: \.checkInID) { photos[id] = group }
    }

    /// Forgets everything, for example after signing out.
    public func clear() {
        generation += 1
        items = []
        photos = [:]
        isLoading = false
        reachedEnd = false
        failure = nil
        hasLoaded = false
    }

    private static func unique(_ page: [FeedItem]) -> [FeedItem] {
        var seen = Set<UUID>()
        return page.filter { seen.insert($0.id).inserted }
    }
}
