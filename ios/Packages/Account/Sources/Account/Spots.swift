import Foundation
import Supabase

/// One spotting location in the list of an airport (`spotting_locations_at`).
public struct SpotLocation: Identifiable, Equatable, Sendable, Decodable {
    public let id: Int
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public let description: String?
    /// `approved`, or `pending` for the caller's own place that still waits for approval.
    public let status: String
    public let mine: Bool
    /// Public sessions held here, plus the caller's own.
    public let sessions: Int

    public init(id: Int, name: String, latitude: Double, longitude: Double, description: String?, status: String, mine: Bool, sessions: Int) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.description = description
        self.status = status
        self.mine = mine
        self.sessions = sessions
    }

    public var isPending: Bool { status == "pending" }
}

/// One spotting location with its numbers (`get_spotting_location`).
public struct SpotDetail: Identifiable, Equatable, Sendable, Decodable {
    public let id: Int
    public let airportID: Int
    public let airport: String
    public let iata: String?
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public let description: String?
    public let bestTime: String?
    public let facing: String?
    public let tips: String?
    public let legalNotes: String?
    public let status: String
    public let mine: Bool
    public let sessions: Int
    public let aircraft: Int
    public let mySessions: Int

    public var isPending: Bool { status == "pending" }

    private enum CodingKeys: String, CodingKey {
        case id, airport, iata, name, latitude, longitude, description, facing, tips, status, mine, sessions, aircraft
        case airportID = "airport_id"
        case bestTime = "best_time"
        case legalNotes = "legal_notes"
        case mySessions = "my_sessions"
    }
}

/// One aircraft seen during a session (`get_visit_sightings`).
public struct VisitSighting: Identifiable, Equatable, Sendable, Decodable {
    public let id: UUID
    public let occurredAt: Date
    public let registration: String?
    public let typeICAO: String?

    public init(id: UUID, occurredAt: Date, registration: String?, typeICAO: String?) {
        self.id = id
        self.occurredAt = occurredAt
        self.registration = registration
        self.typeICAO = typeICAO
    }

    private enum CodingKeys: String, CodingKey {
        case id, registration
        case occurredAt = "occurred_at"
        case typeICAO = "type_icao"
    }
}

/// What a check-in page shows about spotting locations (`get_checkin_spot`).
public struct CheckInSpot: Equatable, Sendable, Decodable {
    public let visitID: UUID
    public let spotID: Int?
    public let spotName: String?
    /// For a visit: how many aircraft are linked to it. `nil` for a sighting.
    public let sightings: Int?

    private enum CodingKeys: String, CodingKey {
        case sightings
        case visitID = "visit_id"
        case spotID = "spot_id"
        case spotName = "spot_name"
    }
}

/// Spotting locations: the places at an airport, one place, and the aircraft of a session.
public protocol SpotBackend: Sendable {
    func spotLocations(at airport: Int) async throws -> [SpotLocation]
    /// `nil` when the place does not exist or is not visible to the caller.
    func spotDetail(_ id: Int) async throws -> SpotDetail?
    func visitSightings(_ visit: UUID) async throws -> [VisitSighting]
    /// `nil` when the check-in is not part of a session or the caller may not see it.
    func checkInSpot(_ checkIn: UUID) async throws -> CheckInSpot?
}

extension SupabaseAccountBackend: SpotBackend {
    public func spotLocations(at airport: Int) async throws -> [SpotLocation] {
        try await mappingErrors { try await client.rpc("spotting_locations_at", params: ["p_airport": airport]).execute().value }
    }

    public func spotDetail(_ id: Int) async throws -> SpotDetail? {
        guard let data = try await rawOrNil("get_spotting_location", params: ["p_id": id]) else { return nil }
        return try JSONDecoder().decode(SpotDetail.self, from: data)
    }

    public func visitSightings(_ visit: UUID) async throws -> [VisitSighting] {
        try await mappingErrors { try await client.rpc("get_visit_sightings", params: ["p_visit": visit]).execute().value }
    }

    public func checkInSpot(_ checkIn: UUID) async throws -> CheckInSpot? {
        guard let data = try await rawOrNil("get_checkin_spot", params: ["p_id": checkIn]) else { return nil }
        return try JSONDecoder().decode(CheckInSpot.self, from: data)
    }

    /// The JSON of an answer, or `nil` for a JSON null (an empty answer).
    private func rawOrNil(_ function: String, params: some Encodable & Sendable) async throws -> Data? {
        let data = try await mappingErrors { try await client.rpc(function, params: params).execute().data }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "null" ? nil : data
    }
}

extension UnconfiguredAccountBackend: SpotBackend {
    public func spotLocations(at airport: Int) async throws -> [SpotLocation] { throw AccountError.notConfigured }
    public func spotDetail(_ id: Int) async throws -> SpotDetail? { throw AccountError.notConfigured }
    public func visitSightings(_ visit: UUID) async throws -> [VisitSighting] { throw AccountError.notConfigured }
    public func checkInSpot(_ checkIn: UUID) async throws -> CheckInSpot? { throw AccountError.notConfigured }
}
