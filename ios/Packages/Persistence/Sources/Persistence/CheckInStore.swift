import Foundation
import SwiftData
import WingspotCore

/// What the user entered. A check-in needs a registration or a type (concept §4.1).
public struct SpottedDraft: Sendable {
    public struct Place: Sendable {
        public let airportID: Int
        public let code: String

        public init(airportID: Int, code: String) {
            self.airportID = airportID
            self.code = code
        }
    }

    public struct AircraftTypeChoice: Sendable {
        public let icaoCode: String
        public let name: String

        public init(icaoCode: String, name: String) {
            self.icaoCode = icaoCode
            self.name = name
        }
    }

    public var registration: Registration?
    public var type: AircraftTypeChoice?
    public var place: Place?
    public var position: GeoCoordinate?
    public var photo: PreparedPhoto?

    public init(
        registration: Registration? = nil, type: AircraftTypeChoice? = nil, place: Place? = nil,
        position: GeoCoordinate? = nil, photo: PreparedPhoto? = nil
    ) {
        self.registration = registration
        self.type = type
        self.place = place
        self.position = position
        self.photo = photo
    }

    public var hasAircraft: Bool { registration != nil || type != nil }
}

public struct SpottedResult: Equatable, Sendable {
    public enum History: Equatable, Sendable {
        case firstTime
        /// `count` includes this check-in.
        case seenBefore(count: Int, lastSeen: Date, lastPlace: String?)
    }

    public let id: UUID
    /// The registration if there is one, otherwise the type code.
    public let subject: String
    public let history: History

    public init(id: UUID, subject: String, history: History) {
        self.id = id
        self.subject = subject
        self.history = history
    }
}

/// Why someone is at an airport (concept §4.3). The raw values are what the server stores.
public enum VisitContext: String, CaseIterable, Sendable {
    case spotting, departing, arriving, transit, working, museum
}

/// What the user entered for an airport visit.
public struct AirportDraft: Sendable {
    public let airportID: Int
    public let code: String
    public var context: VisitContext
    public var position: GeoCoordinate?
    public var photo: PreparedPhoto?
    /// Friends who were there too.
    public var tagged: [UUID]

    public init(
        airportID: Int, code: String, context: VisitContext = .spotting, position: GeoCoordinate? = nil,
        photo: PreparedPhoto? = nil, tagged: [UUID] = []
    ) {
        self.tagged = tagged
        self.airportID = airportID
        self.code = code
        self.context = context
        self.position = position
        self.photo = photo
    }
}

public struct AirportResult: Equatable, Sendable {
    public enum History: Equatable, Sendable {
        case firstTime
        /// `count` includes this check-in. Earlier check-ins of any kind at this airport count.
        case visitedBefore(count: Int, lastVisit: Date)
    }

    public let id: UUID
    public let code: String
    public let history: History

    public init(id: UUID, code: String, history: History) {
        self.id = id
        self.code = code
        self.history = history
    }
}

/// The cabin classes the server knows (concept §4.2). The raw values are what the server stores.
public enum CabinClass: String, CaseIterable, Sendable {
    case economy, premiumEconomy = "premium_economy", business, first
}

/// What the user entered for a flight.
public struct FlownDraft: Sendable {
    public var origin: SpottedDraft.Place
    public var destination: SpottedDraft.Place
    /// The flight's distance in km, worked out on the device for the result screen. The server works out its own.
    public var distanceKm: Int?
    public var flightNumber: String?
    public var registration: Registration?
    public var type: SpottedDraft.AircraftTypeChoice?
    public var cabin: CabinClass?
    public var seat: String?
    public var photo: PreparedPhoto?
    /// Friends who flew with you.
    public var tagged: [UUID]

    public init(
        origin: SpottedDraft.Place, destination: SpottedDraft.Place, distanceKm: Int? = nil, flightNumber: String? = nil,
        registration: Registration? = nil, type: SpottedDraft.AircraftTypeChoice? = nil, cabin: CabinClass? = nil,
        seat: String? = nil, photo: PreparedPhoto? = nil, tagged: [UUID] = []
    ) {
        self.tagged = tagged
        self.photo = photo
        self.origin = origin
        self.destination = destination
        self.distanceKm = distanceKm
        self.flightNumber = flightNumber
        self.registration = registration
        self.type = type
        self.cabin = cabin
        self.seat = seat
    }
}

public struct FlownResult: Equatable, Sendable {
    public let id: UUID
    public let route: String
    public let distanceKm: Int?
    /// How many times this exact route is saved on the device, including this flight.
    public let timesOnRoute: Int

    public init(id: UUID, route: String, distanceKm: Int?, timesOnRoute: Int) {
        self.id = id
        self.route = route
        self.distanceKm = distanceKm
        self.timesOnRoute = timesOnRoute
    }
}

public enum CheckInError: Error, Equatable {
    case sameAirport
    case missingAircraft
}

/// The moment a flight is saved at when only its day is known.
public enum FlightDay {
    /// Today keeps the real time. Any other day uses midday, which stays on that day in any time zone.
    public static func moment(of day: Date, now: Date = Date(), calendar: Calendar = .current) -> Date {
        if calendar.isDate(day, inSameDayAs: now) { return now }
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }
}

@MainActor
public struct CheckInStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Saves locally and reports how often this aircraft was seen before.
    /// `ownerID` is the signed-in user, or `nil` when signed out. Check-ins without an owner go to whoever signs in next.
    public func saveSpotted(_ draft: SpottedDraft, ownerID: UUID? = nil, at date: Date = Date()) throws -> SpottedResult {
        let subject: String
        let earlier: [LocalCheckIn]
        if let registration = draft.registration?.value {
            subject = registration
            earlier = try history(FetchDescriptor(predicate: #Predicate { $0.registration == registration }))
        } else if let code = draft.type?.icaoCode {
            subject = code
            earlier = try history(FetchDescriptor(predicate: #Predicate { $0.typeICAO == code }))
        } else {
            throw CheckInError.missingAircraft
        }

        let id = UUID.v7(at: date)
        context.insert(LocalCheckIn(
            id: id, kind: "spotted", registration: draft.registration?.value,
            typeICAO: draft.type?.icaoCode, typeName: draft.type?.name,
            airportID: draft.place?.airportID, airportCode: draft.place?.code,
            latitude: draft.position?.latitude, longitude: draft.position?.longitude,
            occurredAt: date, syncState: .pending, ownerID: ownerID
        ))
        insertPhoto(draft.photo, for: id, at: date)
        try context.save()

        guard let last = earlier.first else {
            return SpottedResult(id: id, subject: subject, history: .firstTime)
        }
        return SpottedResult(id: id, subject: subject, history: .seenBefore(
            count: earlier.count + 1, lastSeen: last.occurredAt, lastPlace: last.airportCode
        ))
    }

    /// Saves an airport visit locally and reports whether this airport has been seen before.
    public func saveAirport(_ draft: AirportDraft, ownerID: UUID? = nil, at date: Date = Date()) throws -> AirportResult {
        let airportID = draft.airportID
        let earlier = try history(FetchDescriptor(predicate: #Predicate { $0.airportID == airportID }))

        let id = UUID.v7(at: date)
        context.insert(LocalCheckIn(
            id: id, kind: "airport", registration: nil, typeICAO: nil, typeName: nil,
            airportID: draft.airportID, airportCode: draft.code,
            latitude: draft.position?.latitude, longitude: draft.position?.longitude,
            occurredAt: date, syncState: .pending, ownerID: ownerID, visitContext: draft.context.rawValue,
            taggedIDs: draft.tagged.isEmpty ? nil : draft.tagged
        ))
        insertPhoto(draft.photo, for: id, at: date)
        try context.save()

        guard let last = earlier.first else {
            return AirportResult(id: id, code: draft.code, history: .firstTime)
        }
        return AirportResult(id: id, code: draft.code, history: .visitedBefore(count: earlier.count + 1, lastVisit: last.occurredAt))
    }

    /// Saves a flight locally, plus an airport check-in for each end of it. `date` is the day of the flight.
    public func saveFlown(_ draft: FlownDraft, ownerID: UUID? = nil, at date: Date = Date()) throws -> FlownResult {
        guard draft.origin.airportID != draft.destination.airportID else { throw CheckInError.sameAirport }
        let from = draft.origin.airportID
        let to = draft.destination.airportID
        let earlier = try history(FetchDescriptor(predicate: #Predicate {
            $0.kind == "flown" && $0.originID == from && $0.destinationID == to
        }))

        let id = UUID.v7(at: date)
        let flight = draft.flightNumber?.filter { !$0.isWhitespace }.uppercased()
        context.insert(LocalCheckIn(
            id: id, kind: "flown", registration: draft.registration?.value,
            typeICAO: draft.type?.icaoCode, typeName: draft.type?.name, airportID: nil, airportCode: nil,
            latitude: nil, longitude: nil, occurredAt: date, syncState: .pending, ownerID: ownerID,
            originID: from, destinationID: to, originCode: draft.origin.code, destinationCode: draft.destination.code,
            flightNumber: (flight?.isEmpty ?? true) ? nil : flight, cabin: draft.cabin?.rawValue,
            seat: draft.seat?.isEmpty ?? true ? nil : draft.seat?.uppercased(),
            taggedIDs: draft.tagged.isEmpty ? nil : draft.tagged
        ))
        insertPhoto(draft.photo, for: id, at: date)
        // The airports are checked in too, so they count as visited and show on the airport pages.
        for (airport, visit) in [(draft.origin, VisitContext.departing), (draft.destination, .arriving)] {
            context.insert(LocalCheckIn(
                id: UUID.v7(at: date), kind: "airport", registration: nil, typeICAO: nil, typeName: nil,
                airportID: airport.airportID, airportCode: airport.code, latitude: nil, longitude: nil,
                occurredAt: date, syncState: .pending, ownerID: ownerID, visitContext: visit.rawValue, flightID: id
            ))
        }
        try context.save()
        return FlownResult(
            id: id, route: "\(draft.origin.code) → \(draft.destination.code)", distanceKm: draft.distanceKm,
            timesOnRoute: earlier.count + 1
        )
    }

    /// Corrects the details of a saved flight and sends them again. The route and the photos stay as they were.
    /// A new `occurredAt` moves the flight, and the two airport visits it created, to that time.
    /// Returns `false` when this device has no such flight, for example one made on another device.
    @discardableResult
    public func updateFlown(
        id: UUID, registration: Registration?, type: SpottedDraft.AircraftTypeChoice?, flightNumber: String?,
        cabin: CabinClass?, seat: String?, occurredAt: Date? = nil, tagged: [UUID]? = nil
    ) throws -> Bool {
        let matches = try context.fetch(FetchDescriptor<LocalCheckIn>(predicate: #Predicate { $0.id == id && $0.kind == "flown" }))
        guard let flight = matches.first else { return false }
        let number = flightNumber?.filter { !$0.isWhitespace }.uppercased()
        let seat = seat?.trimmingCharacters(in: .whitespaces).uppercased()
        flight.registration = registration?.value
        flight.typeICAO = type?.icaoCode
        flight.typeName = type?.name
        flight.flightNumber = (number?.isEmpty ?? true) ? nil : number
        flight.cabin = cabin?.rawValue
        flight.seat = (seat?.isEmpty ?? true) ? nil : seat
        if let tagged { flight.taggedIDs = tagged }
        // The server takes the corrected details when the flight is sent again.
        if let occurredAt, occurredAt != flight.occurredAt {
            // The airport visits a flight creates share its time. The server moves its copies the same way.
            let old = flight.occurredAt
            let owner = flight.ownerID
            let flightID = flight.id
            let airports = [flight.originID, flight.destinationID].compactMap { $0 }
            let visits = try context.fetch(FetchDescriptor<LocalCheckIn>(predicate: #Predicate { $0.kind == "airport" }))
            for visit in visits where visit.ownerID == owner
                && (visit.visitContext == "departing" || visit.visitContext == "arriving")
                && (visit.flightID == flightID
                    || (visit.flightID == nil && visit.occurredAt == old && airports.contains(visit.airportID ?? -1))) {
                visit.occurredAt = occurredAt
            }
            flight.occurredAt = occurredAt
        }
        flight.syncState = SyncState.pending.rawValue
        flight.syncError = nil
        try context.save()
        return true
    }

    /// Corrects the aircraft of a saved sighting and sends it again. Needs a registration or a type, like a new sighting.
    /// Returns `false` when this device has no such sighting.
    @discardableResult
    public func updateSpotted(id: UUID, registration: Registration?, type: SpottedDraft.AircraftTypeChoice?) throws -> Bool {
        let matches = try context.fetch(FetchDescriptor<LocalCheckIn>(predicate: #Predicate { $0.id == id && $0.kind == "spotted" }))
        guard let sighting = matches.first, registration != nil || type != nil else { return false }
        sighting.registration = registration?.value
        sighting.typeICAO = type?.icaoCode
        sighting.typeName = type?.name
        sighting.syncState = SyncState.pending.rawValue
        sighting.syncError = nil
        try context.save()
        return true
    }

    /// Corrects the reason for a saved airport visit and sends it again.
    /// Returns `false` when this device has no such visit.
    @discardableResult
    public func updateVisit(id: UUID, reason: VisitContext, tagged: [UUID]? = nil) throws -> Bool {
        let matches = try context.fetch(FetchDescriptor<LocalCheckIn>(predicate: #Predicate { $0.id == id && $0.kind == "airport" }))
        guard let visit = matches.first else { return false }
        visit.visitContext = reason.rawValue
        if let tagged { visit.taggedIDs = tagged }
        visit.syncState = SyncState.pending.rawValue
        visit.syncError = nil
        try context.save()
        return true
    }

    /// Removes a check-in from this device, with its photos. Does nothing if there is none.
    /// Deleting a flight also removes the two airport visits it created, as the server does: the visits linked to it,
    /// and for visits without a link the ones `updateFlown` would find by time and airports, unless another flight at
    /// the same time still uses the airport.
    /// Returns the ids of everything removed, so the lists on screen can drop them too.
    @discardableResult
    public func deleteLocal(id: UUID) throws -> [UUID] {
        var removed = [UUID]()
        let found = try context.fetch(FetchDescriptor<LocalCheckIn>(predicate: #Predicate { $0.id == id }))
        for checkIn in found where checkIn.kind == "flown" {
            let time = checkIn.occurredAt
            let owner = checkIn.ownerID
            let airports = [checkIn.originID, checkIn.destinationID].compactMap { $0 }
            let others = try context.fetch(FetchDescriptor<LocalCheckIn>(predicate: #Predicate {
                $0.kind == "flown" && $0.occurredAt == time && $0.id != id
            })).filter { $0.ownerID == owner }
            let stillUsed = Set(others.flatMap { [$0.originID, $0.destinationID].compactMap { $0 } })
            let visits = try context.fetch(FetchDescriptor<LocalCheckIn>(predicate: #Predicate { $0.kind == "airport" }))
            for visit in visits where visit.ownerID == owner
                && (visit.visitContext == "departing" || visit.visitContext == "arriving") {
                if visit.flightID == id {
                    removed.append(visit.id)
                } else if visit.flightID == nil, visit.occurredAt == time, airports.contains(visit.airportID ?? -1),
                          !stillUsed.contains(visit.airportID ?? -1) {
                    removed.append(visit.id)
                }
            }
        }
        removed.append(contentsOf: found.map(\.id))
        for gone in removed {
            for checkIn in try context.fetch(FetchDescriptor<LocalCheckIn>(predicate: #Predicate { $0.id == gone })) {
                context.delete(checkIn)
            }
            for photo in try context.fetch(FetchDescriptor<LocalPhoto>(predicate: #Predicate { $0.checkInID == gone })) {
                context.delete(photo)
            }
        }
        try context.save()
        return removed
    }

    /// The aircraft types of your earlier flights with this flight number, the most recent first, each type once.
    /// A flight being edited is left out, so its own type isn't offered back.
    public func recentTypes(
        forFlight flightNumber: String, userID: UUID?, excluding excluded: UUID? = nil, limit: Int = 5
    ) throws -> [SpottedDraft.AircraftTypeChoice] {
        let number = flightNumber.filter { !$0.isWhitespace }.uppercased()
        guard !number.isEmpty else { return [] }
        let flights = try history(FetchDescriptor<LocalCheckIn>(predicate: #Predicate {
            $0.kind == "flown" && $0.flightNumber == number && $0.typeICAO != nil
        }))
        var seen = Set<String>()
        var types = [SpottedDraft.AircraftTypeChoice]()
        for flight in CheckInStats.counted(flights, userID: userID) where flight.id != excluded {
            guard let code = flight.typeICAO, seen.insert(code).inserted else { continue }
            types.append(.init(icaoCode: code, name: flight.typeName ?? code))
            if types.count == limit { break }
        }
        return types
    }

    /// The aircraft types you checked in most recently, newest first, each once, from sightings and flights.
    public func recentTypes(userID: UUID?, limit: Int = 5) throws -> [SpottedDraft.AircraftTypeChoice] {
        let withType = try history(FetchDescriptor<LocalCheckIn>(predicate: #Predicate { $0.typeICAO != nil }))
        var seen = Set<String>()
        var types = [SpottedDraft.AircraftTypeChoice]()
        for checkIn in CheckInStats.counted(withType, userID: userID) {
            guard let code = checkIn.typeICAO, seen.insert(code).inserted else { continue }
            types.append(.init(icaoCode: code, name: checkIn.typeName ?? code))
            if types.count == limit { break }
        }
        return types
    }

    /// The airports you checked in at most recently, newest first, each once: where you spotted or visited, and
    /// where your flights started and ended.
    public func recentAirportIDs(userID: UUID?, limit: Int = 5) throws -> [Int] {
        var seen = Set<Int>()
        var ids = [Int]()
        // A flight and the two visits it created share their time. The flight goes first, so its destination leads.
        let newestFirst = CheckInStats.counted(try history(FetchDescriptor<LocalCheckIn>()), userID: userID)
            .enumerated().sorted {
                if $0.element.occurredAt != $1.element.occurredAt { return $0.element.occurredAt > $1.element.occurredAt }
                if ($0.element.kind == "flown") != ($1.element.kind == "flown") { return $0.element.kind == "flown" }
                return $0.offset < $1.offset
            }.map(\.element)
        for checkIn in newestFirst {
            let airports = checkIn.kind == "flown" ? [checkIn.destinationID, checkIn.originID] : [checkIn.airportID]
            for case let id? in airports where seen.insert(id).inserted {
                ids.append(id)
                if ids.count == limit { return ids }
            }
        }
        return ids
    }

    /// The most photos one check-in can have. The server refuses more.
    public static let maxPhotos = 4

    /// How many photos of this check-in are waiting on, or were sent from, this device. Refused ones don't count.
    public func photoCount(for checkInID: UUID) throws -> Int {
        let refused = SyncState.rejected.rawValue
        return try context.fetchCount(FetchDescriptor<LocalPhoto>(predicate: #Predicate {
            $0.checkInID == checkInID && $0.syncState != refused
        }))
    }

    /// Adds a photo to a check-in that was saved earlier. It goes up with the next sync.
    /// Returns `false` when this device has no such check-in or it already has the most photos.
    @discardableResult
    public func addPhoto(_ photo: PreparedPhoto, to checkInID: UUID, at date: Date = Date()) throws -> Bool {
        let matches = try context.fetchCount(FetchDescriptor<LocalCheckIn>(predicate: #Predicate { $0.id == checkInID }))
        guard matches > 0, try photoCount(for: checkInID) < Self.maxPhotos else { return false }
        insertPhoto(photo, for: checkInID, at: date)
        try context.save()
        return true
    }

    /// Saved together with the check-in, so a photo never exists without it.
    private func insertPhoto(_ photo: PreparedPhoto?, for checkInID: UUID, at date: Date) {
        guard let photo else { return }
        context.insert(LocalPhoto(
            id: UUID.v7(at: date), checkInID: checkInID, jpeg: photo.jpeg, width: photo.width, height: photo.height,
            createdAt: date
        ))
    }

    private func history(_ descriptor: FetchDescriptor<LocalCheckIn>) throws -> [LocalCheckIn] {
        var descriptor = descriptor
        descriptor.sortBy = [SortDescriptor(\.occurredAt, order: .reverse)]
        return try context.fetch(descriptor)
    }
}
