import Account
import Foundation
import Persistence
import WingspotCore

/// Sends photos to the Wingspot API as the signed-in user.
struct APIPhotoUploader: PhotoUploader {
    /// `nil` when this build has no API address. Nothing is sent, and the photos keep waiting.
    let client: APIClient?
    let accessToken: @Sendable () async -> String?

    func upload(photoID: UUID, checkInID: UUID, jpeg: Data) async throws -> PhotoUploadOutcome {
        guard let client else { throw URLError(.badURL) }
        guard let token = await accessToken() else { throw APIError.unexpectedStatus(401) }
        return try await client.uploadPhoto(checkInID: checkInID, photoID: photoID, jpeg: jpeg, accessToken: token)
    }
}
