import Foundation
import GRDB
import WingspotCore

public struct AircraftType: Hashable, Identifiable, Sendable {
    public let icaoCode: String
    public let manufacturer: String
    public let model: String

    public var id: String { icaoCode }
    public var name: String { "\(manufacturer) \(model)" }

    public init(icaoCode: String, manufacturer: String, model: String) {
        self.icaoCode = icaoCode
        self.manufacturer = manufacturer
        self.model = model
    }
}

public struct Airport: Hashable, Identifiable, Sendable {
    public let id: Int
    public let icao: String?
    public let iata: String?
    public let name: String
    public let city: String?
    public let coordinate: GeoCoordinate

    /// The shortest label people recognize: IATA, then ICAO, then the name.
    public var code: String { iata ?? icao ?? name }

    public init(id: Int, icao: String?, iata: String?, name: String, city: String?, coordinate: GeoCoordinate) {
        self.id = id
        self.icao = icao
        self.iata = iata
        self.name = name
        self.city = city
        self.coordinate = coordinate
    }
}

public enum ReferenceDataError: Error, Equatable {
    case unsupportedSchema(Int)
    case insecureURL
    case sizeMismatch
    case checksumMismatch
    case downloadFailed(Int)
}

/// Read-only access to the on-device reference database (contracts/refdata/schema.sql).
public struct ReferenceDatabase: Sendable {
    /// The schema version of contracts/refdata/schema.sql that this code understands.
    public static let supportedSchemaVersion = 2

    public let dataVersion: String
    private let queue: DatabaseQueue

    /// Throws if the file can't be opened or has a schema this code doesn't support.
    public init(path: String) throws {
        var configuration = Configuration()
        configuration.readonly = true
        let queue = try DatabaseQueue(path: path, configuration: configuration)
        let version = try queue.read { db in
            let schema = try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
            guard schema == Self.supportedSchemaVersion else {
                throw ReferenceDataError.unsupportedSchema(schema)
            }
            return try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = 'data_version'") ?? ""
        }
        self.queue = queue
        self.dataVersion = version
    }

    /// Finds types by code, maker or model, with an exact code first.
    public func searchTypes(_ text: String, limit: Int = 30) async throws -> [AircraftType] {
        guard let query = SearchQuery.fts(text) else { return [] }
        let code = text.trimmingCharacters(in: .whitespaces).uppercased()
        return try await queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT t.icao_code, t.manufacturer, t.model
                FROM aircraft_types_fts f
                JOIN aircraft_types t ON t.icao_code = f.icao_code
                WHERE aircraft_types_fts MATCH ?
                ORDER BY t.icao_code = ? DESC, f.rank
                LIMIT ?
                """, arguments: [query, code, limit]
            ).map { AircraftType(icaoCode: $0["icao_code"], manufacturer: $0["manufacturer"], model: $0["model"]) }
        }
    }

    /// Finds airports by name, city, code or keyword, with exact codes and then large airports first.
    public func searchAirports(_ text: String, limit: Int = 30) async throws -> [Airport] {
        guard let query = SearchQuery.fts(text) else { return [] }
        let code = text.trimmingCharacters(in: .whitespaces).uppercased()
        return try await queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT a.* FROM airports_fts f
                JOIN airports a ON a.id = f.rowid
                WHERE airports_fts MATCH ?
                ORDER BY a.iata = ? DESC, a.icao = ? DESC,
                  CASE a.type WHEN 'large_airport' THEN 0 WHEN 'medium_airport' THEN 1 ELSE 2 END,
                  a.default_search DESC, f.rank
                LIMIT ?
                """, arguments: [query, code, code, limit]
            ).map(Self.airport)
        }
    }

    public func airport(id: Int) async throws -> Airport? {
        try await queue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM airports WHERE id = ?", arguments: [id]).map(Self.airport)
        }
    }

    /// The airport with this IATA code, such as `FRA`. Boarding passes carry IATA codes.
    public func airport(iata: String) async throws -> Airport? {
        let code = iata.trimmingCharacters(in: .whitespaces).uppercased()
        return try await queue.read { db in
            try Row.fetchOne(db, sql: """
                SELECT * FROM airports WHERE iata = ?
                ORDER BY CASE type WHEN 'large_airport' THEN 0 WHEN 'medium_airport' THEN 1 ELSE 2 END, default_search DESC
                LIMIT 1
                """, arguments: [code]).map(Self.airport)
        }
    }

    /// The airport someone at this position is most likely at: the nearest one with an IATA code or scheduled
    /// service within 15 km, otherwise any nearby airfield within 5 km. Heliports don't count.
    public func nearestAirport(to position: GeoCoordinate) async throws -> Airport? {
        let latitudeRange = 15.0 / 111.0
        let candidates = try await queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM airports
                WHERE latitude BETWEEN ? AND ?
                  AND type NOT IN ('heliport', 'balloonport', 'seaplane_base')
                """, arguments: [position.latitude - latitudeRange, position.latitude + latitudeRange]
            ).map { (airport: Self.airport($0), isMajor: ($0["default_search"] as Int) == 1) }
        }
        let ranked = candidates
            .map { (candidate: $0, distance: GreatCircle.distanceKm(from: position, to: $0.airport.coordinate)) }
            .sorted { $0.distance < $1.distance }
        let match = ranked.first { $0.candidate.isMajor && $0.distance <= 15 } ?? ranked.first { $0.distance <= 5 }
        return match?.candidate.airport
    }

    /// Airports with an IATA code (the ones people know and travel through) within `radiusKm`, nearest first.
    /// Heliports, balloon ports and seaplane bases don't count.
    public func airports(near position: GeoCoordinate, withinKm radiusKm: Double = 150, limit: Int = 10) async throws
        -> [(airport: Airport, distanceKm: Double)] {
        let latitudeRange = radiusKm / 111.0
        let longitudeRange = radiusKm / (111.0 * max(0.1, cos(position.latitude * .pi / 180)))
        let candidates = try await queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM airports
                WHERE latitude BETWEEN ? AND ? AND longitude BETWEEN ? AND ?
                  AND iata IS NOT NULL AND iata <> ''
                  AND type NOT IN ('heliport', 'balloonport', 'seaplane_base')
                """, arguments: [
                    position.latitude - latitudeRange, position.latitude + latitudeRange,
                    position.longitude - longitudeRange, position.longitude + longitudeRange,
                ]
            ).map(Self.airport)
        }
        return candidates
            .map { (airport: $0, distanceKm: GreatCircle.distanceKm(from: position, to: $0.coordinate)) }
            .filter { $0.distanceKm <= radiusKm }
            .sorted { $0.distanceKm < $1.distanceKm }
            .prefix(limit)
            .map { $0 }
    }

    private static func airport(_ row: Row) -> Airport {
        Airport(
            id: row["id"], icao: row["icao"], iata: row["iata"], name: row["name"], city: row["city"],
            coordinate: GeoCoordinate(latitude: row["latitude"], longitude: row["longitude"])
        )
    }
}
