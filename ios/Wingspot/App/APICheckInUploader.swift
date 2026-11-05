import Account
import Foundation
import Persistence
import WingspotCore

/// Sends check-ins to the Wingspot API as the signed-in user.
struct APICheckInUploader: CheckInUploader {
    /// `nil` when this build has no API address. Nothing is sent, and the check-ins keep waiting.
    let client: APIClient?
    let accessToken: @Sendable () async -> String?

    func upload(_ items: [CheckInUploadItem]) async throws -> [CheckInUploadResult] {
        guard let client else { throw URLError(.badURL) }
        // No token means the session expired or is gone: the outbox keeps the check-ins and tries again later.
        guard let token = await accessToken() else { throw APIError.unexpectedStatus(401) }
        return try await client.uploadCheckins(items, accessToken: token)
    }
}
