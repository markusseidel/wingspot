import Foundation
import SwiftData

/// One of the signed-in person's own check-ins as the server has it (`get_my_checkins`).
public struct RemoteCheckIn: Sendable, Equatable {
    public let id: UUID
    public let kind: String
    public let occurredAt: Date
    /// The time exactly as the server sent it. Paging sends it back unchanged, because rounding it would skip or repeat rows.
    public let cursorTime: String
    public let registration: String?
    public let typeICAO: String?
    public let airportID: Int?
    public let airportCode: String?
    public let originID: Int?
    public let destinationID: Int?
    public let originCode: String?
    public let destinationCode: String?
    public let flightNumber: String?
    public let cabin: String?
    public let seat: String?
    public let visitContext: String?
    public let latitude: Double?
    public let longitude: Double?

    public init(
        id: UUID, kind: String, occurredAt: Date, cursorTime: String, registration: String? = nil, typeICAO: String? = nil,
        airportID: Int? = nil, airportCode: String? = nil, originID: Int? = nil, destinationID: Int? = nil,
        originCode: String? = nil, destinationCode: String? = nil, flightNumber: String? = nil, cabin: String? = nil,
        seat: String? = nil, visitContext: String? = nil, latitude: Double? = nil, longitude: Double? = nil
    ) {
        self.id = id
        self.kind = kind
        self.occurredAt = occurredAt
        self.cursorTime = cursorTime
        self.registration = registration
        self.typeICAO = typeICAO
        self.airportID = airportID
        self.airportCode = airportCode
        self.originID = originID
        self.destinationID = destinationID
        self.originCode = originCode
        self.destinationCode = destinationCode
        self.flightNumber = flightNumber
        self.cabin = cabin
        self.seat = seat
        self.visitContext = visitContext
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Where the person's own check-ins come from. Tests replace it.
public protocol CheckInSource: Sendable {
    /// One page, oldest first, after the check-in with this time (as the server sent it) and id.
    /// - Throws: for anything that should be tried again later, such as no network or a server error.
    func myCheckIns(after cursor: (time: String, id: UUID)?, pageSize: Int) async throws -> [RemoteCheckIn]
}

/// Puts the signed-in person's check-ins that this device doesn't have (a new phone, a reinstall) back in the local
/// store, once per account and device, so the profile numbers, collections and the map work there too. Check-ins that
/// are already here are left as they are.
@MainActor
public final class CheckInRestorer {
    public static let pageSize = 200

    private let context: ModelContext
    private let source: CheckInSource
    private let defaults: UserDefaults
    private var isRunning = false

    public init(context: ModelContext, source: CheckInSource, defaults: UserDefaults = .standard) {
        self.context = context
        self.source = source
        self.defaults = defaults
    }

    private func key(_ userID: UUID) -> String { "restoredCheckIns.\(userID.uuidString.lowercased())" }

    public func wasRestored(for userID: UUID) -> Bool { defaults.bool(forKey: key(userID)) }

    /// Forgets that this account was restored, for example after its data was erased from the device.
    public func forget(userID: UUID) { defaults.removeObject(forKey: key(userID)) }

    public func restore(userID: UUID) async -> OutboxOutcome {
        guard !isRunning, !wasRestored(for: userID) else { return .idle }
        isRunning = true
        defer { isRunning = false }

        var cursor: (time: String, id: UUID)?
        var added = 0
        while true {
            let page: [RemoteCheckIn]
            do {
                page = try await source.myCheckIns(after: cursor, pageSize: Self.pageSize)
            } catch {
                return .retryLater(stored: added, rejected: 0)
            }
            added += insert(page, userID: userID)
            guard page.count >= Self.pageSize, let last = page.last else { break }
            cursor = (last.cursorTime, last.id)
        }
        defaults.set(true, forKey: key(userID))
        return added > 0 ? .finished(stored: added, rejected: 0) : .idle
    }

    private func insert(_ page: [RemoteCheckIn], userID: UUID) -> Int {
        let ids = page.map(\.id)
        let have = Set(((try? context.fetch(FetchDescriptor<LocalCheckIn>(predicate: #Predicate { ids.contains($0.id) }))) ?? []).map(\.id))
        var added = 0
        for remote in page where !have.contains(remote.id) {
            let checkIn = LocalCheckIn(
                id: remote.id, kind: remote.kind, registration: remote.registration, typeICAO: remote.typeICAO, typeName: nil,
                airportID: remote.airportID, airportCode: remote.airportCode, latitude: remote.latitude, longitude: remote.longitude,
                occurredAt: remote.occurredAt, syncState: .synced, ownerID: userID, visitContext: remote.visitContext,
                originID: remote.originID, destinationID: remote.destinationID, originCode: remote.originCode,
                destinationCode: remote.destinationCode, flightNumber: remote.flightNumber, cabin: remote.cabin, seat: remote.seat
            )
            checkIn.syncedAt = Date()
            context.insert(checkIn)
            added += 1
        }
        if added > 0 { try? context.save() }
        return added
    }
}
