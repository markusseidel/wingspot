import Foundation
import SwiftData
import WingspotCore

/// Sends check-ins to the server (`POST /v1/checkins`). Tests replace it.
public protocol CheckInUploader: Sendable {
    /// - Throws: for anything that should be tried again later, such as no network or a server error.
    func upload(_ items: [CheckInUploadItem]) async throws -> [CheckInUploadResult]
}

public enum OutboxOutcome: Equatable, Sendable {
    /// Nothing was waiting.
    case idle
    /// Everything that was waiting got an answer. Some items may have been rejected.
    case finished(stored: Int, rejected: Int)
    /// Something is still waiting and a later attempt may work.
    case retryLater(stored: Int, rejected: Int)
}

/// The offline outbox (concept §11.2). Check-ins are saved on the device first, and this uploads
/// them. Repeating an upload is safe, because the server stores each id once: if a response gets
/// lost, the next attempt hears `stored` for the same ids and the check-in is never duplicated.
@MainActor
public final class CheckInOutbox {
    /// The API accepts at most 50 per call.
    public static let batchSize = 50

    private let context: ModelContext
    private let uploader: CheckInUploader
    private var isSyncing = false

    public init(context: ModelContext, uploader: CheckInUploader) {
        self.context = context
        self.uploader = uploader
    }

    public func pendingCount(for userID: UUID) throws -> Int {
        try pending(for: userID).count
    }

    /// Uploads what waits for `userID`: their own check-ins, and those made while signed out.
    /// Check-ins that belong to another account stay where they are. Runs one at a time.
    public func sync(userID: UUID) async -> OutboxOutcome {
        guard !isSyncing else { return .idle }
        isSyncing = true
        defer { isSyncing = false }

        reopenFixable(for: userID)
        var stored = 0
        var rejected = 0
        var sawWork = false
        while true {
            let batch = Array(((try? pending(for: userID)) ?? []).prefix(Self.batchSize))
            if batch.isEmpty { break }
            sawWork = true

            // Claim the signed-out ones now, so a failed attempt can't hand them to another account later.
            for checkIn in batch where checkIn.ownerID == nil { checkIn.ownerID = userID }
            try? context.save()

            let answers: [CheckInUploadResult]
            do {
                answers = try await uploadKeepingTheCore(batch)
            } catch {
                // Only the server's answer for an item can reject it. A failed request, whatever the reason
                // (no network, a server error, a missing endpoint before a deploy, an expired token), leaves
                // everything waiting, so a later app or server update can still send it.
                return .retryLater(stored: stored, rejected: rejected)
            }

            var unanswered = false
            let byID = Dictionary(answers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for checkIn in batch {
                guard let answer = byID[checkIn.id] else {
                    unanswered = true
                    continue
                }
                if answer.isStored {
                    checkIn.syncState = SyncState.synced.rawValue
                    checkIn.syncedAt = Date()
                    checkIn.syncError = nil
                    stored += 1
                } else if answer.isRejected {
                    reject(checkIn, code: answer.code ?? answer.status)
                    rejected += 1
                } else {
                    // A status from a newer server. Keep the check-in waiting rather than guess.
                    unanswered = true
                }
            }
            try? context.save()
            // An item without a usable answer stays pending. Stop, or this loop would ask again at once.
            if unanswered { return .retryLater(stored: stored, rejected: rejected) }
        }
        return sawWork ? .finished(stored: stored, rejected: rejected) : .idle
    }

    /// A detail the server doesn't accept (an aircraft type it doesn't know, an odd flight number) must not cost
    /// the whole check-in: the item is sent again without that detail, which stays on the device.
    private func uploadKeepingTheCore(_ batch: [LocalCheckIn]) async throws -> [CheckInUploadResult] {
        var dropped: [UUID: Set<Detail>] = [:]
        var last: [UUID: CheckInUploadResult] = [:]
        var remaining = batch
        for _ in 0..<5 {
            let answers = try await uploader.upload(remaining.map { Self.item($0, without: dropped[$0.id] ?? []) })
            let byID = Dictionary(answers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var again: [LocalCheckIn] = []
            for checkIn in remaining {
                guard let answer = byID[checkIn.id] else { continue }
                last[checkIn.id] = answer
                if answer.isRejected, let detail = Self.droppableDetail(for: answer.code, in: checkIn),
                   dropped[checkIn.id]?.contains(detail) != true {
                    dropped[checkIn.id, default: []].insert(detail)
                    again.append(checkIn)
                }
            }
            if again.isEmpty { break }
            remaining = again
        }
        return Array(last.values)
    }

    /// Items an earlier version of the app left rejected for a detail that is now dropped when sending.
    private func reopenFixable(for userID: UUID) {
        let rejected = SyncState.rejected.rawValue
        let items = (try? context.fetch(FetchDescriptor<LocalCheckIn>(predicate: #Predicate { $0.syncState == rejected }))) ?? []
        var changed = false
        for checkIn in items where checkIn.ownerID == nil || checkIn.ownerID == userID {
            if Self.droppableDetail(for: checkIn.syncError, in: checkIn) != nil {
                checkIn.syncState = SyncState.pending.rawValue
                checkIn.syncError = nil
                changed = true
            }
        }
        if changed { try? context.save() }
    }

    private enum Detail { case type, flightNumber, cabin, seat, registration }

    /// The detail the server refused, if it is one a flight can do without and the check-in has it.
    private static func droppableDetail(for code: String?, in checkIn: LocalCheckIn) -> Detail? {
        guard checkIn.kind == "flown" else { return nil }
        switch code {
        case "unknown_type": return checkIn.typeICAO == nil ? nil : .type
        case "invalid_flight_number": return checkIn.flightNumber == nil ? nil : .flightNumber
        case "invalid_cabin": return checkIn.cabin == nil ? nil : .cabin
        case "invalid_seat": return checkIn.seat == nil ? nil : .seat
        case "invalid_registration": return checkIn.registration == nil ? nil : .registration
        default: return nil
        }
    }

    private func pending(for userID: UUID) throws -> [LocalCheckIn] {
        let pending = SyncState.pending.rawValue
        var descriptor = FetchDescriptor<LocalCheckIn>(predicate: #Predicate { $0.syncState == pending })
        descriptor.sortBy = [SortDescriptor(\.occurredAt)]
        return try context.fetch(descriptor).filter { $0.ownerID == nil || $0.ownerID == userID }
    }

    private func reject(_ checkIn: LocalCheckIn, code: String) {
        checkIn.syncState = SyncState.rejected.rawValue
        checkIn.syncError = code
    }

    private static func item(_ checkIn: LocalCheckIn, without dropped: Set<Detail> = []) -> CheckInUploadItem {
        CheckInUploadItem(
            id: checkIn.id, kind: checkIn.kind, occurredAt: checkIn.occurredAt,
            registration: dropped.contains(.registration) ? nil : checkIn.registration,
            typeICAO: dropped.contains(.type) ? nil : checkIn.typeICAO, airportID: checkIn.airportID,
            latitude: checkIn.latitude, longitude: checkIn.longitude, context: checkIn.visitContext,
            originID: checkIn.originID, destinationID: checkIn.destinationID,
            flightNumber: dropped.contains(.flightNumber) ? nil : checkIn.flightNumber,
            cabin: dropped.contains(.cabin) ? nil : checkIn.cabin, seat: dropped.contains(.seat) ? nil : checkIn.seat
        )
    }
}
