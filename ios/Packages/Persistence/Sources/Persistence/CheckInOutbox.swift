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
                answers = try await uploader.upload(batch.map(Self.item))
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

    private static func item(_ checkIn: LocalCheckIn) -> CheckInUploadItem {
        CheckInUploadItem(
            id: checkIn.id, kind: checkIn.kind, occurredAt: checkIn.occurredAt, registration: checkIn.registration,
            typeICAO: checkIn.typeICAO, airportID: checkIn.airportID, latitude: checkIn.latitude,
            longitude: checkIn.longitude, context: checkIn.visitContext,
            originID: checkIn.originID, destinationID: checkIn.destinationID, flightNumber: checkIn.flightNumber,
            cabin: checkIn.cabin, seat: checkIn.seat
        )
    }
}
