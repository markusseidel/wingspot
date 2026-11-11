import Foundation
import SwiftData

/// Flights saved before a flight checked in its two airports get those airport check-ins now.
/// An airport that already has a check-in on the day of the flight is left alone.
@MainActor
public struct FlightAirportBackfill {
    private let context: ModelContext
    private let calendar: Calendar

    public init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    /// - Returns: how many airport check-ins were added.
    @discardableResult
    public func run() throws -> Int {
        let all = try context.fetch(FetchDescriptor<LocalCheckIn>())
        let flights = all.filter { $0.kind == "flown" && $0.syncState != SyncState.rejected.rawValue }
        guard !flights.isEmpty else { return 0 }

        // Day and airport pairs that are already covered, for every account on this device.
        struct Visit: Hashable { let owner: UUID?; let airport: Int; let day: Date }
        var covered = Set<Visit>()
        for checkIn in all where checkIn.kind == "airport" {
            guard let airport = checkIn.airportID else { continue }
            covered.insert(Visit(owner: checkIn.ownerID, airport: airport, day: calendar.startOfDay(for: checkIn.occurredAt)))
        }

        var added = 0
        for flight in flights {
            let day = calendar.startOfDay(for: flight.occurredAt)
            let ends: [(Int?, String?, VisitContext)] = [
                (flight.originID, flight.originCode, .departing),
                (flight.destinationID, flight.destinationCode, .arriving),
            ]
            for (airportID, code, visit) in ends {
                guard let airportID, let code else { continue }
                let key = Visit(owner: flight.ownerID, airport: airportID, day: day)
                guard !covered.contains(key) else { continue }
                covered.insert(key)
                context.insert(LocalCheckIn(
                    id: UUID.v7(at: flight.occurredAt), kind: "airport", registration: nil, typeICAO: nil, typeName: nil,
                    airportID: airportID, airportCode: code, latitude: nil, longitude: nil,
                    occurredAt: flight.occurredAt, syncState: .pending, ownerID: flight.ownerID, visitContext: visit.rawValue
                ))
                added += 1
            }
        }
        if added > 0 { try context.save() }
        return added
    }
}
