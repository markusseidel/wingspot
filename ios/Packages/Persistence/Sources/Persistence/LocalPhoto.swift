import Foundation
import SwiftData

/// A photo on this device, waiting to go up with its check-in. The JPEG has no metadata (see `PhotoPreparer`).
/// New models open an existing store without a migration step.
@Model
public final class LocalPhoto {
    @Attribute(.unique) public var id: UUID
    public var checkInID: UUID
    @Attribute(.externalStorage) public var jpeg: Data
    public var width: Int
    public var height: Int
    public var createdAt: Date
    public var syncState: String
    /// Why the server refused it, once `syncState` is `rejected`.
    public var syncError: String?

    init(id: UUID, checkInID: UUID, jpeg: Data, width: Int, height: Int, createdAt: Date) {
        self.id = id
        self.checkInID = checkInID
        self.jpeg = jpeg
        self.width = width
        self.height = height
        self.createdAt = createdAt
        self.syncState = SyncState.pending.rawValue
    }
}
