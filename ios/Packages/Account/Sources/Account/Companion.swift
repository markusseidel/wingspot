import Foundation

/// A friend's flight or airport visit you are tagged on and have not taken over yet (`get_companion_requests`, #273).
public struct CompanionRequest: Identifiable, Hashable, Sendable, Decodable {
    public var id: UUID { checkInID }
    public let checkInID: UUID
    public let authorID: UUID
    public let username: String
    public let displayName: String?
    /// `flown` or `airport`.
    public let kind: String
    public let occurredAt: Date
    public let flightNumber: String?
    public let originID: Int?
    public let destinationID: Int?
    public let originCode: String?
    public let destinationCode: String?
    public let airportID: Int?
    public let airportCode: String?
    public let distanceKm: Int?
    public let requestedAt: Date?

    /// The name to show: the display name if there is one.
    public var who: String { displayName ?? username }

    /// "FRA → JFK", or the airport's code for a visit.
    public var title: String {
        if kind == "flown", let from = originCode, let to = destinationCode { return from + " → " + to }
        return airportCode ?? "?"
    }

    public init(
        checkInID: UUID, authorID: UUID, username: String, displayName: String? = nil, kind: String, occurredAt: Date,
        flightNumber: String? = nil, originID: Int? = nil, destinationID: Int? = nil, originCode: String? = nil,
        destinationCode: String? = nil, airportID: Int? = nil, airportCode: String? = nil, distanceKm: Int? = nil, requestedAt: Date? = nil
    ) {
        self.checkInID = checkInID
        self.authorID = authorID
        self.username = username
        self.displayName = displayName
        self.kind = kind
        self.occurredAt = occurredAt
        self.flightNumber = flightNumber
        self.originID = originID
        self.destinationID = destinationID
        self.originCode = originCode
        self.destinationCode = destinationCode
        self.airportID = airportID
        self.airportCode = airportCode
        self.distanceKm = distanceKm
        self.requestedAt = requestedAt
    }

    private enum CodingKeys: String, CodingKey {
        case username, kind
        case checkInID = "checkin_id"
        case authorID = "author_id"
        case displayName = "display_name"
        case occurredAt = "occurred_at"
        case flightNumber = "flight_number"
        case originID = "origin_id"
        case destinationID = "destination_id"
        case originCode = "origin_code"
        case destinationCode = "destination_code"
        case airportID = "airport_id"
        case airportCode = "airport_code"
        case distanceKm = "distance_km"
        case requestedAt = "requested_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        checkInID = try c.decode(UUID.self, forKey: .checkInID)
        authorID = try c.decode(UUID.self, forKey: .authorID)
        username = try c.decode(String.self, forKey: .username)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        kind = try c.decode(String.self, forKey: .kind)
        occurredAt = try Self.date(c, .occurredAt)
        flightNumber = try c.decodeIfPresent(String.self, forKey: .flightNumber)
        originID = try c.decodeIfPresent(Int.self, forKey: .originID)
        destinationID = try c.decodeIfPresent(Int.self, forKey: .destinationID)
        originCode = try c.decodeIfPresent(String.self, forKey: .originCode)
        destinationCode = try c.decodeIfPresent(String.self, forKey: .destinationCode)
        airportID = try c.decodeIfPresent(Int.self, forKey: .airportID)
        airportCode = try c.decodeIfPresent(String.self, forKey: .airportCode)
        distanceKm = try c.decodeIfPresent(Int.self, forKey: .distanceKm)
        requestedAt = try c.decodeIfPresent(String.self, forKey: .requestedAt).flatMap(FeedItem.parse)
    }

    private static func date(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> Date {
        let text = try c.decode(String.self, forKey: key)
        guard let date = FeedItem.parse(text) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "Not a date: \(text)")
        }
        return date
    }
}

/// One of your own flights that is the same flight as the one you were tagged on (`find_matching_flight`).
public struct MatchingFlight: Identifiable, Hashable, Sendable, Decodable {
    public let id: UUID
    /// `number` (the same flight number) or `route` (the same two airports close in time).
    public let reason: String
    public let secondsApart: Int
    public let flightNumber: String?
    public let occurredAt: Date
    public let originCode: String?
    public let destinationCode: String?

    public init(id: UUID, reason: String, secondsApart: Int, flightNumber: String?, occurredAt: Date, originCode: String?, destinationCode: String?) {
        self.id = id
        self.reason = reason
        self.secondsApart = secondsApart
        self.flightNumber = flightNumber
        self.occurredAt = occurredAt
        self.originCode = originCode
        self.destinationCode = destinationCode
    }

    private enum CodingKeys: String, CodingKey {
        case id, reason
        case secondsApart = "seconds_apart"
        case flightNumber = "flight_number"
        case occurredAt = "occurred_at"
        case originCode = "origin_code"
        case destinationCode = "destination_code"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        reason = try c.decode(String.self, forKey: .reason)
        secondsApart = try c.decodeIfPresent(Int.self, forKey: .secondsApart) ?? 0
        flightNumber = try c.decodeIfPresent(String.self, forKey: .flightNumber)
        let time = try c.decode(String.self, forKey: .occurredAt)
        guard let date = FeedItem.parse(time) else {
            throw DecodingError.dataCorruptedError(forKey: .occurredAt, in: c, debugDescription: "Not a date: \(time)")
        }
        occurredAt = date
        originCode = try c.decodeIfPresent(String.self, forKey: .originCode)
        destinationCode = try c.decodeIfPresent(String.self, forKey: .destinationCode)
    }
}

/// The flight facts a "Replace the flight data" took over from the friend's flight (`replace_flight_data`), for the app to copy into its own.
public struct ReplacedFlight: Equatable, Sendable, Decodable {
    public let flightNumber: String?
    public let originID: Int
    public let destinationID: Int
    public let occurredAt: Date
    public let registration: String?
    public let typeICAO: String?
    public let distanceKm: Int?

    public init(flightNumber: String?, originID: Int, destinationID: Int, occurredAt: Date, registration: String?, typeICAO: String?, distanceKm: Int?) {
        self.flightNumber = flightNumber
        self.originID = originID
        self.destinationID = destinationID
        self.occurredAt = occurredAt
        self.registration = registration
        self.typeICAO = typeICAO
        self.distanceKm = distanceKm
    }

    private enum CodingKeys: String, CodingKey {
        case registration
        case flightNumber = "flight_number"
        case originID = "origin_id"
        case destinationID = "destination_id"
        case occurredAt = "occurred_at"
        case typeICAO = "type_icao"
        case distanceKm = "distance_km"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        flightNumber = try c.decodeIfPresent(String.self, forKey: .flightNumber)
        originID = try c.decode(Int.self, forKey: .originID)
        destinationID = try c.decode(Int.self, forKey: .destinationID)
        let time = try c.decode(String.self, forKey: .occurredAt)
        guard let date = FeedItem.parse(time) else {
            throw DecodingError.dataCorruptedError(forKey: .occurredAt, in: c, debugDescription: "Not a date: \(time)")
        }
        occurredAt = date
        registration = try c.decodeIfPresent(String.self, forKey: .registration)
        typeICAO = try c.decodeIfPresent(String.self, forKey: .typeICAO)
        distanceKm = try c.decodeIfPresent(Int.self, forKey: .distanceKm)
    }
}

/// What the person chose when the friend's flight is one they already have.
public enum CompanionChoice: Sendable {
    /// Link the two check-ins and change nothing else.
    case keepMine
    /// Take the flight facts over into the flight they have.
    case replace
}
