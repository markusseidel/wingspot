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
    /// The airport's ID in the reference data, for opening its page.
    public let airportID: Int?
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
        airportCode: String? = nil, airportID: Int? = nil, originCode: String? = nil, destinationCode: String? = nil,
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
        self.airportID = airportID
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
            airportCode: airportCode, airportID: airportID, originCode: originCode, destinationCode: destinationCode,
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
        case airportID = "airport_id"
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
        airportID = try c.decodeIfPresent(Int.self, forKey: .airportID)
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

/// A few numbers about one airport over the last 30 days, among the check-ins the caller may see.
public struct AirportActivity: Equatable, Sendable, Decodable {
    public struct Spotter: Equatable, Sendable, Identifiable, Decodable {
        public let userID: UUID
        public let username: String
        public let displayName: String?
        public let checkIns: Int
        public var id: UUID { userID }

        public init(userID: UUID, username: String, displayName: String? = nil, checkIns: Int) {
            self.userID = userID
            self.username = username
            self.displayName = displayName
            self.checkIns = checkIns
        }

        private enum CodingKeys: String, CodingKey {
            case username
            case userID = "user_id"
            case displayName = "display_name"
            case checkIns = "checkins"
        }
    }

    public let checkIns: Int
    public let aircraft: Int
    public let topSpotters: [Spotter]

    public init(checkIns: Int, aircraft: Int, topSpotters: [Spotter] = []) {
        self.checkIns = checkIns
        self.aircraft = aircraft
        self.topSpotters = topSpotters
    }

    private enum CodingKeys: String, CodingKey {
        case aircraft
        case checkIns = "checkins_30d"
        case aircraft30 = "aircraft_30d"
        case topSpotters = "top_spotters"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        checkIns = try c.decodeIfPresent(Int.self, forKey: .checkIns) ?? 0
        aircraft = try c.decodeIfPresent(Int.self, forKey: .aircraft30) ?? 0
        topSpotters = try c.decodeIfPresent([Spotter].self, forKey: .topSpotters) ?? []
    }
}

/// A few numbers about one aircraft type over the last 30 days, among the check-ins the caller may see.
public struct TypeActivity: Equatable, Sendable, Decodable {
    public let checkIns: Int
    public let airports: Int
    public let topSpotters: [AirportActivity.Spotter]

    public init(checkIns: Int, airports: Int, topSpotters: [AirportActivity.Spotter] = []) {
        self.checkIns = checkIns
        self.airports = airports
        self.topSpotters = topSpotters
    }

    private enum CodingKeys: String, CodingKey {
        case checkIns = "checkins_30d"
        case airports = "airports_30d"
        case topSpotters = "top_spotters"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        checkIns = try c.decodeIfPresent(Int.self, forKey: .checkIns) ?? 0
        airports = try c.decodeIfPresent(Int.self, forKey: .airports) ?? 0
        topSpotters = try c.decodeIfPresent([AirportActivity.Spotter].self, forKey: .topSpotters) ?? []
    }
}

/// An airport with many check-ins lately, among those the caller may see.
public struct ActiveAirport: Equatable, Sendable, Identifiable, Decodable {
    public let airportID: Int
    public let code: String
    public let name: String
    public let city: String?
    public let checkIns: Int
    public let people: Int
    public var id: Int { airportID }

    public init(airportID: Int, code: String, name: String, city: String? = nil, checkIns: Int, people: Int) {
        self.airportID = airportID
        self.code = code
        self.name = name
        self.city = city
        self.checkIns = checkIns
        self.people = people
    }

    private enum CodingKeys: String, CodingKey {
        case people, city
        case airportID = "airport_id"
        case code = "airport_code"
        case name = "airport_name"
        case checkIns = "checkins"
    }
}

public protocol FeedBackend: Sendable {
    func feed(after cursor: FeedCursor?, pageSize: Int) async throws -> [FeedItem]
    /// One person's check-ins that the caller may see, newest first.
    func personCheckIns(of person: UUID, after cursor: FeedCursor?, pageSize: Int) async throws -> [FeedItem]
    /// The check-ins at one airport that the caller may see, newest first.
    func airportCheckIns(at airport: Int, after cursor: FeedCursor?, pageSize: Int) async throws -> [FeedItem]
    func airportActivity(at airport: Int) async throws -> AirportActivity
    /// The check-ins of one aircraft type that the caller may see, newest first.
    func typeCheckIns(of type: String, after cursor: FeedCursor?, pageSize: Int) async throws -> [FeedItem]
    func typeActivity(of type: String) async throws -> TypeActivity
    /// The airports with the most check-ins in the last `days` days, busiest first.
    func activeAirports(days: Int, limit: Int) async throws -> [ActiveAirport]
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

    /// Told after the person saluted or commented, so the app can offer notifications at a good moment.
    @ObservationIgnored public var onSocialAction: (@MainActor () -> Void)?

    private let backend: FeedBackend
    /// A person's page lists only their check-ins. `nil` is the Feed tab.
    private let person: UUID?
    /// An airport's page lists the check-ins there.
    private let airport: Int?
    /// An aircraft type's page lists the check-ins of that type (its ICAO code).
    private let type: String?
    private let reactions: ReactionBackend
    private let userID: @MainActor () -> UUID?
    /// Changes whenever the list restarts, so an answer to an older request is dropped.
    private var generation = 0

    public init(backend: FeedBackend, reactions: ReactionBackend, person: UUID? = nil, airport: Int? = nil, type: String? = nil,
                userID: @escaping @MainActor () -> UUID?) {
        self.backend = backend
        self.person = person
        self.airport = airport
        self.type = type
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
            if on { onSocialAction?() }
        } catch {
            if let now = items.firstIndex(where: { $0.id == id }) { items[now] = items[now].updating(salutes: before.salutes, saluted: before.saluted) }
            failure = (error as? AccountError) ?? .unknown
        }
    }

    /// A list of one person's check-ins, with the same cards, salutes and comments as the feed.
    public func personStore(for id: UUID) -> FeedStore {
        let store = FeedStore(backend: backend, reactions: reactions, person: id, userID: userID)
        store.onSocialAction = onSocialAction
        return store
    }

    /// A list of the check-ins at one airport.
    public func airportStore(for id: Int) -> FeedStore {
        let store = FeedStore(backend: backend, reactions: reactions, airport: id, userID: userID)
        store.onSocialAction = onSocialAction
        return store
    }

    /// A list of the check-ins of one aircraft type.
    public func typeStore(for code: String) -> FeedStore {
        let store = FeedStore(backend: backend, reactions: reactions, type: code, userID: userID)
        store.onSocialAction = onSocialAction
        return store
    }

    /// The counts for one aircraft type page.
    public func typeActivity(of code: String) async throws -> TypeActivity {
        try await backend.typeActivity(of: code)
    }

    /// The counts for one airport page.
    public func airportActivity(at id: Int) async throws -> AirportActivity {
        try await backend.airportActivity(at: id)
    }

    /// The busiest airports lately, for the Explore tab.
    public func activeAirports(days: Int = 7, limit: Int = 10) async throws -> [ActiveAirport] {
        try await backend.activeAirports(days: days, limit: limit)
    }

    /// The comments of one check-in. Its count is kept in step with the card.
    public func commentStore(for id: UUID) -> CheckInCommentStore {
        CheckInCommentStore(
            checkIn: id, backend: reactions, userID: userID,
            onCountChange: { [weak self] count in self?.setCommentCount(count, for: id) },
            onPosted: { [weak self] in self?.onSocialAction?() }
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
            let page = try await fetch(after: nil)
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
            let page = try await fetch(after: FeedCursor(time: last.cursorTime, id: last.id))
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

    private func fetch(after cursor: FeedCursor?) async throws -> [FeedItem] {
        if let person {
            return try await backend.personCheckIns(of: person, after: cursor, pageSize: Self.pageSize)
        }
        if let type {
            return try await backend.typeCheckIns(of: type, after: cursor, pageSize: Self.pageSize)
        }
        if let airport {
            return try await backend.airportCheckIns(at: airport, after: cursor, pageSize: Self.pageSize)
        }
        return try await backend.feed(after: cursor, pageSize: Self.pageSize)
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
