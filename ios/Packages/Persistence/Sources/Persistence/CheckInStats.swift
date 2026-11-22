import Foundation
import WingspotCore

/// The numbers on the profile, worked out from the check-ins on this device so they work offline.
/// Check-ins the server refused are left out, because the server doesn't count them either.
public struct CheckInStats: Equatable, Sendable {
    public var checkIns = 0
    public var sightings = 0
    public var airportVisits = 0
    public var flights = 0
    /// Different registrations seen.
    public var aircraft = 0
    /// Different aircraft types, from sightings and flights.
    public var types = 0
    /// The airports checked in at, by spotting or visiting, including the two airports a flight checks in.
    public var airportIDs = Set<Int>()
    public var airports: Int { airportIDs.count }

    /// A flight's two airports. Its distance is worked out from where the airports are.
    public struct Route: Hashable, Sendable {
        public let origin: Int
        public let destination: Int
    }
    /// How many flights were flown on each route.
    public var routes = [Route: Int]()

    /// A flight and its airports, to look for its saved route.
    public struct Flight: Hashable, Sendable {
        public let id: UUID
        public let origin: Int
        public let destination: Int
    }
    /// Every flight with its two airports.
    public var flightList = [Flight]()

    public init() {}

    /// The check-ins that count: not refused by the server, and this account's or made signed out.
    public static func counted(_ all: [LocalCheckIn], userID: UUID?) -> [LocalCheckIn] {
        all.filter { checkIn in
            if checkIn.syncState == SyncState.rejected.rawValue { return false }
            if let userID, let owner = checkIn.ownerID, owner != userID { return false }
            return true
        }
    }

    /// - Parameter userID: the signed-in account. Its check-ins and those made signed out count. `nil` counts everything.
    public init(_ all: [LocalCheckIn], userID: UUID?) {
        var registrations = Set<String>()
        var typeCodes = Set<String>()
        for checkIn in Self.counted(all, userID: userID) {
            checkIns += 1
            switch checkIn.kind {
            case "spotted":
                sightings += 1
                if let airport = checkIn.airportID { airportIDs.insert(airport) }
            case "airport":
                airportVisits += 1
                if let airport = checkIn.airportID { airportIDs.insert(airport) }
            case "flown":
                flights += 1
                if let origin = checkIn.originID, let destination = checkIn.destinationID {
                    routes[Route(origin: origin, destination: destination), default: 0] += 1
                    flightList.append(Flight(id: checkIn.id, origin: origin, destination: destination))
                }
            default:
                break
            }
            if let registration = checkIn.registration { registrations.insert(registration) }
            if let type = checkIn.typeICAO { typeCodes.insert(type) }
        }
        aircraft = registrations.count
        types = typeCodes.count
    }

    /// The kilometres flown: the great-circle distance of each flight, rounded as the server does.
    /// Flights whose airports are not known are left out.
    public func kilometres(coordinate: (Int) -> GeoCoordinate?) -> Int {
        routes.reduce(0) { total, entry in
            guard let from = coordinate(entry.key.origin), let to = coordinate(entry.key.destination) else { return total }
            return total + Int(GreatCircle.distanceKm(from: from, to: to).rounded()) * entry.value
        }
    }
}
