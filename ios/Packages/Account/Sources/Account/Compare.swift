import Foundation
import Supabase

/// The numbers of one side of a comparison.
public struct CompareStats: Equatable, Sendable, Decodable {
    public let flights: Int
    public let distanceKm: Int
    public let airports: Int
    public let countries: Int
    public let airlines: Int
    public let types: Int

    public init(flights: Int, distanceKm: Int, airports: Int, countries: Int, airlines: Int, types: Int) {
        self.flights = flights
        self.distanceKm = distanceKm
        self.airports = airports
        self.countries = countries
        self.airlines = airlines
        self.types = types
    }

    private enum CodingKeys: String, CodingKey {
        case flights, airports, countries, airlines, types
        case distanceKm = "distance_km"
    }
}

/// An airport, country, airline or aircraft type in a comparison. A country has only a code.
public struct CompareItem: Hashable, Sendable, Decodable, Identifiable {
    public let code: String
    public let name: String?
    public var id: String { code }

    public init(code: String, name: String? = nil) {
        self.code = code
        self.name = name
    }
}

/// What is in both lists, only in yours and only in theirs.
public struct CompareSet: Equatable, Sendable, Decodable {
    public let common: [CompareItem]
    public let mine: [CompareItem]
    public let theirs: [CompareItem]

    public init(common: [CompareItem] = [], mine: [CompareItem] = [], theirs: [CompareItem] = []) {
        self.common = common
        self.mine = mine
        self.theirs = theirs
    }
}

/// You next to a friend, as `compare_with` answers. Only what you may see of them is in it.
public struct CompareResult: Equatable, Sendable, Decodable {
    public let me: CompareStats
    public let them: CompareStats
    public let airports: CompareSet
    public let countries: CompareSet
    public let airlines: CompareSet
    public let types: CompareSet

    public init(me: CompareStats, them: CompareStats, airports: CompareSet, countries: CompareSet, airlines: CompareSet, types: CompareSet) {
        self.me = me
        self.them = them
        self.airports = airports
        self.countries = countries
        self.airlines = airlines
        self.types = types
    }

    public static func decode(_ data: Data) throws -> CompareResult {
        try JSONDecoder().decode(CompareResult.self, from: data)
    }
}

public protocol CompareBackend: Sendable {
    /// The JSON of the answer, or `nil` when their profile can't be seen.
    func compare(with id: UUID) async throws -> Data?
}

extension SupabaseAccountBackend: CompareBackend {
    public func compare(with id: UUID) async throws -> Data? {
        let data = try await mappingErrors { try await client.rpc("compare_with", params: ["p_target": id]).execute().data }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "null" ? nil : data
    }
}

extension UnconfiguredAccountBackend: CompareBackend {
    public func compare(with id: UUID) async throws -> Data? { throw AccountError.notConfigured }
}
