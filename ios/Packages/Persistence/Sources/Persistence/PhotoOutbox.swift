import Foundation
import SwiftData
import WingspotCore

/// Sends one photo to the server. Tests replace it.
public protocol PhotoUploader: Sendable {
    /// - Throws: for anything that should be tried again later, such as no network or a server error.
    func upload(photoID: UUID, checkInID: UUID, jpeg: Data) async throws -> PhotoUploadOutcome
}

/// Uploads the photos of check-ins the server already has. A photo goes up only after its check-in is stored, because
/// the server attaches it to that check-in. Like the check-in outbox, every failed request leaves the photo waiting,
/// and only the server's answer for a photo can reject it.
@MainActor
public final class PhotoOutbox {
    private let context: ModelContext
    private let uploader: PhotoUploader
    private var isSyncing = false

    public init(context: ModelContext, uploader: PhotoUploader) {
        self.context = context
        self.uploader = uploader
    }

    public func sync(userID: UUID) async -> OutboxOutcome {
        guard !isSyncing else { return .idle }
        isSyncing = true
        defer { isSyncing = false }

        var stored = 0
        var rejected = 0
        var sawWork = false
        var mustRetry = false
        for photo in waitingPhotos() {
            guard let checkIn = checkIn(for: photo), checkIn.ownerID == userID else { continue }
            switch SyncState(rawValue: checkIn.syncState) {
            case .rejected:
                // The check-in will never be on the server, so the photo has nowhere to go.
                photo.syncState = SyncState.rejected.rawValue
                photo.syncError = "checkin_rejected"
                sawWork = true
                rejected += 1
                continue
            case .synced:
                break
            default:
                // Still waiting. The check-in outbox sends it first, and then this runs again.
                continue
            }
            sawWork = true

            let outcome: PhotoUploadOutcome
            do {
                outcome = try await uploader.upload(photoID: photo.id, checkInID: photo.checkInID, jpeg: photo.jpeg)
            } catch {
                mustRetry = true
                break
            }
            switch outcome {
            case .stored:
                photo.syncState = SyncState.synced.rawValue
                photo.syncError = nil
                stored += 1
            case .rejected(let code):
                photo.syncState = SyncState.rejected.rawValue
                photo.syncError = code
                rejected += 1
            case .checkInNotThereYet:
                mustRetry = true
            }
            try? context.save()
            if mustRetry { break }
        }
        try? context.save()
        if mustRetry { return .retryLater(stored: stored, rejected: rejected) }
        return sawWork ? .finished(stored: stored, rejected: rejected) : .idle
    }

    private func waitingPhotos() -> [LocalPhoto] {
        let pending = SyncState.pending.rawValue
        var descriptor = FetchDescriptor<LocalPhoto>(predicate: #Predicate { $0.syncState == pending })
        descriptor.sortBy = [SortDescriptor(\.createdAt)]
        return (try? context.fetch(descriptor)) ?? []
    }

    private func checkIn(for photo: LocalPhoto) -> LocalCheckIn? {
        let id = photo.checkInID
        return try? context.fetch(FetchDescriptor<LocalCheckIn>(predicate: #Predicate { $0.id == id })).first
    }
}
