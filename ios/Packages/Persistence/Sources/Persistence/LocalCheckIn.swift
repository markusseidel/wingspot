import Foundation
import SwiftData

public enum SyncState: String, Sendable {
    case pending
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

    init(
        id: UUID, kind: String, registration: String?, typeICAO: String?, typeName: String?, airportID: Int?,
        airportCode: String?, latitude: Double?, longitude: Double?, occurredAt: Date, syncState: SyncState
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
    }
}
