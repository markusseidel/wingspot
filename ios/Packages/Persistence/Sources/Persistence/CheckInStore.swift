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

    public init(
        registration: Registration? = nil, type: AircraftTypeChoice? = nil, place: Place? = nil,
        position: GeoCoordinate? = nil
    ) {
        self.registration = registration
        self.type = type
        self.place = place
        self.position = position
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

    public init(airportID: Int, code: String, context: VisitContext = .spotting, position: GeoCoordinate? = nil) {
        self.airportID = airportID
        self.code = code
        self.context = context
        self.position = position
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

public enum CheckInError: Error, Equatable {
    case missingAircraft
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
            occurredAt: date, syncState: .pending, ownerID: ownerID, visitContext: draft.context.rawValue
        ))
        try context.save()

        guard let last = earlier.first else {
            return AirportResult(id: id, code: draft.code, history: .firstTime)
        }
        return AirportResult(id: id, code: draft.code, history: .visitedBefore(count: earlier.count + 1, lastVisit: last.occurredAt))
    }

    private func history(_ descriptor: FetchDescriptor<LocalCheckIn>) throws -> [LocalCheckIn] {
        var descriptor = descriptor
        descriptor.sortBy = [SortDescriptor(\.occurredAt, order: .reverse)]
        return try context.fetch(descriptor)
    }
}
