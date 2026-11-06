import Foundation
import SwiftData

public enum SyncState: String, Sendable {
    /// Waiting to upload.
    case pending
    /// The server has it.
    case synced
    /// The server refused it for good, so uploading again would get the same answer. It stays on the device.
    case rejected
}

/// A check-in on this device. The server becomes the source of truth once sync exists (concept §11.2).
@Model
public final class LocalCheckIn {
    @Attribute(.unique) public var id: UUID
    public var kind: String
    public var registration: String?
    public var typeICAO: String?
    public var typeName: String?
    public var airportID: Int?
    public var airportCode: String?
    public var latitude: Double?
    public var longitude: Double?
    public var occurredAt: Date
    public var syncState: String
    /// Whose account this check-in belongs to. `nil` while it was made signed out: it goes to whoever signs in next.
    /// New optional properties like these open an existing store without a migration step.
    public var ownerID: UUID?
    public var syncedAt: Date?
    /// Why the server refused it, once `syncState` is `rejected`.
    public var syncError: String?
    /// Why the user was at the airport. Only for airport check-ins. Like `ownerID`, it opens an existing store without a migration step.
    public var visitContext: String?
    /// Flown check-ins only. The route, with the codes kept so the list can show it offline.
    public var originID: Int?
    public var destinationID: Int?
    public var originCode: String?
    public var destinationCode: String?
    public var flightNumber: String?
    public var cabin: String?
    public var seat: String?

    init(
        id: UUID, kind: String, registration: String?, typeICAO: String?, typeName: String?, airportID: Int?,
        airportCode: String?, latitude: Double?, longitude: Double?, occurredAt: Date, syncState: SyncState,
        ownerID: UUID? = nil, visitContext: String? = nil,
        originID: Int? = nil, destinationID: Int? = nil, originCode: String? = nil, destinationCode: String? = nil,
        flightNumber: String? = nil, cabin: String? = nil, seat: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.registration = registration
        self.typeICAO = typeICAO
        self.typeName = typeName
        self.airportID = airportID
        self.airportCode = airportCode
        self.latitude = latitude
        self.longitude = longitude
        self.occurredAt = occurredAt
        self.syncState = syncState.rawValue
        self.ownerID = ownerID
        self.visitContext = visitContext
        self.originID = originID
        self.destinationID = destinationID
        self.originCode = originCode
        self.destinationCode = destinationCode
        self.flightNumber = flightNumber
        self.cabin = cabin
        self.seat = seat
    }
}
