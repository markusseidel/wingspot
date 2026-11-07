import Foundation
import SwiftData

/// Removes what one account left on this iPhone, for example after it was deleted on the server.
/// Check-ins made while signed out (no owner) and other accounts' data stay.
@MainActor
public struct AccountEraser {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func erase(userID: UUID) throws {
        let checkIns = try context.fetch(FetchDescriptor<LocalCheckIn>(predicate: #Predicate { $0.ownerID == userID }))
        let ids = Set(checkIns.map(\.id))
        if !ids.isEmpty {
            // Pictures wait here for their upload and aren't linked to the check-in by a relationship.
            for photo in try context.fetch(FetchDescriptor<LocalPhoto>()) where ids.contains(photo.checkInID) {
                context.delete(photo)
            }
        }
        for checkIn in checkIns { context.delete(checkIn) }
        for ack in try context.fetch(FetchDescriptor<BadgeAck>(predicate: #Predicate { $0.userID == userID })) {
            context.delete(ack)
        }
        for account in try context.fetch(FetchDescriptor<BadgeAccount>(predicate: #Predicate { $0.userID == userID })) {
            context.delete(account)
        }
        try context.save()
    }
}
