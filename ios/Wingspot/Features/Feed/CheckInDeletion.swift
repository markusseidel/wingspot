import Foundation
import Account
import Persistence
import SwiftData

/// Deletes one of your own check-ins for good: on the server, on this device and from the lists on screen.
@MainActor
enum CheckInDeletion {
    /// Returns `false` when the server could not be reached or refused, so the check-in is still there.
    /// One that never reached the server only has to go from this device.
    static func delete(_ id: UUID, feed: FeedStore, others: [FeedStore] = [], context: ModelContext) async -> Bool {
        let local = (try? context.fetch(FetchDescriptor<LocalCheckIn>(predicate: #Predicate { $0.id == id })))?.first
        let neverSent = local.map { $0.syncedAt == nil && $0.syncState == SyncState.pending.rawValue } ?? false
        let removed = await feed.deleteCheckIn(id)
        guard removed || neverSent else { return false }
        try? CheckInStore(context: context).deleteLocal(id: id)
        feed.remove(id)
        for list in others { list.remove(id) }
        return true
    }
}
