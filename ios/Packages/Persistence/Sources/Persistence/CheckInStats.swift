import Foundation

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
    /// Different airports checked in at, by spotting or visiting. A flight's airports don't count, as on the server.
    public var airports = 0

    public init() {}

    /// - Parameter userID: the signed-in account. Its check-ins and those made signed out count. `nil` counts everything.
    public init(_ all: [LocalCheckIn], userID: UUID?) {
        var registrations = Set<String>()
        var typeCodes = Set<String>()
        var airportIDs = Set<Int>()
        for checkIn in all {
            if checkIn.syncState == SyncState.rejected.rawValue { continue }
            if let userID, let owner = checkIn.ownerID, owner != userID { continue }
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
            default:
                break
            }
            if let registration = checkIn.registration { registrations.insert(registration) }
            if let type = checkIn.typeICAO { typeCodes.insert(type) }
        }
        aircraft = registrations.count
        types = typeCodes.count
        airports = airportIDs.count
    }
}
