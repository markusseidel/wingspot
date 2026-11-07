import Foundation
import SwiftData
import Testing
import WingspotCore
@testable import Persistence

@MainActor
private func makeContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: LocalCheckIn.self, LocalPhoto.self, BadgeAck.self, BadgeAccount.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return ModelContext(container)
}

private let a388 = SpottedDraft.AircraftTypeChoice(icaoCode: "A388", name: "Airbus A380-800")

@MainActor @Test func erasingAnAccountLeavesOtherPeoplesDataAlone() throws {
    let context = try makeContext()
    let store = CheckInStore(context: context)
    let me = UUID(), other = UUID()
    let draft = { (registration: String) in SpottedDraft(registration: Registration(registration), type: a388) }
    _ = try store.saveSpotted(draft("DAIMA"), ownerID: me)
    let withPhoto = try store.saveSpotted(draft("DAIMB"), ownerID: me)
    context.insert(LocalPhoto(id: UUID(), checkInID: withPhoto.id, jpeg: Data([1]), width: 1, height: 1, createdAt: Date()))
    _ = try store.saveSpotted(draft("DAIMC"), ownerID: other)
    _ = try store.saveSpotted(draft("DAIMD"), ownerID: nil)
    context.insert(BadgeAck(userID: me, badgeID: "logbook", level: 1))
    context.insert(BadgeAck(userID: other, badgeID: "logbook", level: 1))
    context.insert(BadgeAccount(userID: me, firstSeenAt: Date()))
    context.insert(BadgeAccount(userID: other, firstSeenAt: Date()))
    try context.save()

    try AccountEraser(context: context).erase(userID: me)

    let left = try context.fetch(FetchDescriptor<LocalCheckIn>())
    #expect(Set(left.map(\.ownerID)) == [other, nil])
    #expect(left.count == 2)
    #expect(try context.fetch(FetchDescriptor<LocalPhoto>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<BadgeAck>()).map(\.userID) == [other])
    #expect(try context.fetch(FetchDescriptor<BadgeAccount>()).map(\.userID) == [other])
}
