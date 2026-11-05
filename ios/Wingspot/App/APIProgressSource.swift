import Foundation
import Persistence
import WingspotCore

/// Fetches the signed-in user's progress from the Wingspot API.
struct APIProgressSource: ProgressSource {
    /// `nil` when this build has no API address.
    let client: APIClient?
    let accessToken: @Sendable () async -> String?

    func progress() async throws -> (progress: UserProgress, raw: Data) {
        guard let client else { throw URLError(.badURL) }
        guard let token = await accessToken() else { throw APIError.unexpectedStatus(401) }
        return try await client.progress(accessToken: token)
    }
}
