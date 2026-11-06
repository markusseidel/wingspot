import Foundation
import OSLog
import Supabase

private let logger = Logger(subsystem: "site.wingspot.ios", category: "account")

/// Email sign-in and profile access through Supabase. The client keeps the session in the Keychain.
public struct SupabaseAccountBackend: AccountBackend {
    private static let redirectURL = URL(string: "wingspot://auth-callback")!

    private let client: SupabaseClient

    public init(url: URL, publishableKey: String) {
        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: publishableKey,
            options: SupabaseClientOptions(auth: .init(
                redirectToURL: Self.redirectURL,
                flowType: .pkce,
                emitLocalSessionAsInitialSession: true
            ))
        )
    }

    public func currentUserID() async -> UUID? {
        client.auth.currentSession?.user.id
    }

    public func accessToken() async -> String? {
        // Refreshes the session if it expired, and throws if there is none or the refresh failed.
        try? await client.auth.session.accessToken
    }

    public func sendSignInLink(email: String, language: String?) async throws {
        try await mappingErrors {
            try await client.auth.signInWithOTP(
                email: email,
                redirectTo: Self.redirectURL,
                data: language.map { ["language": .string($0)] }
            )
        }
    }

    public func completeSignIn(from url: URL) async throws -> UUID {
        do {
            return try await client.auth.session(from: url).user.id
        } catch let error as URLError {
            throw Self.map(error)
        } catch {
            // Don't log or pass on the error itself: it can include parts of the link.
            let code = (error as? AuthError)?.errorCode.rawValue ?? String(reflecting: type(of: error))
            logger.error("Sign-in link failed: \(code, privacy: .public)")
            throw AccountError.invalidLink
        }
    }

    public func signInWithApple(idToken: String, nonce: String) async throws -> UUID {
        try await mappingErrors {
            try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
            ).user.id
        }
    }

    public func loadProfile(id: UUID) async throws -> Profile {
        try await mappingErrors {
            let row: ProfileRow = try await client.from("profiles")
                .select("id, username, display_name")
                .eq("id", value: id)
                .single()
                .execute()
                .value
            // home_airport isn't readable directly, only through get_profile.
            let details: ProfileDetails = try await client
                .rpc("get_profile", params: ["target": id])
                .single()
                .execute()
                .value
            return Profile(
                id: row.id, username: row.username, displayName: row.displayName,
                homeAirportID: details.homeAirport
            )
        }
    }

    public func saveProfile(_ profile: Profile) async throws {
        try await mappingErrors {
            _ = try await client.from("profiles")
                // Not asking for the row back, because home_airport isn't readable directly.
                .update(ProfileUpdate(profile), returning: .minimal)
                .eq("id", value: profile.id)
                .execute()
        }
    }

    public func signOut() async throws {
        // Local scope also works offline. Other devices stay signed in.
        try await mappingErrors {
            try await client.auth.signOut(scope: .local)
        }
    }

    private func mappingErrors<T: Sendable>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch let error as URLError {
            throw Self.map(error)
        } catch let error as PostgrestError where error.code == "23505" {
            throw AccountError.usernameTaken
        } catch let error as AuthError {
            switch error.errorCode {
            case .overEmailSendRateLimit, .overRequestRateLimit: throw AccountError.tooManyRequests
            case .providerDisabled: throw AccountError.appleUnavailable
            case .validationFailed: throw AccountError.invalidEmail
            default:
                logger.error("Account request failed: \(error.errorCode.rawValue, privacy: .public)")
                throw AccountError.unknown
            }
        } catch {
            logger.error("Account request failed: \(String(reflecting: type(of: error)), privacy: .public)")
            throw AccountError.unknown
        }
    }

    private static func map(_ error: URLError) -> AccountError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost,
             .cannotFindHost, .dataNotAllowed, .internationalRoamingOff:
            .offline
        default:
            .unknown
        }
    }
}

private struct ProfileRow: Decodable {
    let id: UUID
    let username: String
    let displayName: String?

    private enum CodingKeys: String, CodingKey {
        case id, username
        case displayName = "display_name"
    }
}

private struct ProfileDetails: Decodable {
    let homeAirport: Int?

    private enum CodingKeys: String, CodingKey {
        case homeAirport = "home_airport"
    }
}

private struct ProfileUpdate: Encodable {
    let username: String
    let displayName: String?
    let homeAirport: Int?

    init(_ profile: Profile) {
        username = profile.username
        displayName = profile.displayName
        homeAirport = profile.homeAirportID
    }

    private enum CodingKeys: String, CodingKey {
        case username
        case displayName = "display_name"
        case homeAirport = "home_airport"
    }

    /// Writes empty values as `null`, so clearing a field reaches the database.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(username, forKey: .username)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(homeAirport, forKey: .homeAirport)
    }
}
