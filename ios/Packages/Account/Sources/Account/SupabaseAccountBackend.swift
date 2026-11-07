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

    public func deleteAccount() async throws {
        try await mappingErrors {
            // The function acts on the person whose token is sent, which the client adds.
            try await client.functions.invoke("me", options: FunctionInvokeOptions(method: .delete))
        }
    }

    public func exportMyData() async throws -> Data {
        try await mappingErrors {
            try await client.rpc("export_my_data").execute().data
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


// MARK: - Social

extension SupabaseAccountBackend: SocialBackend {
    public func searchPeople(_ text: String, excluding me: UUID, limit: Int) async throws -> [PersonRecord] {
        try await socialErrors {
            let rows: [PersonRow] = try await client.from("profiles")
                .select("id, username, display_name, is_private")
                .ilike("username", pattern: "%\(text)%")
                .neq("id", value: me)
                .order("username")
                .limit(limit)
                .execute()
                .value
            return rows.map(\.record)
        }
    }

    public func relationships(of me: UUID, among ids: [UUID]) async throws -> (following: Set<UUID>, followers: Set<UUID>) {
        guard !ids.isEmpty else { return ([], []) }
        return try await socialErrors {
            let following: [FollowRow] = try await client.from("follows").select("follower, followee")
                .eq("follower", value: me).in("followee", values: ids).execute().value
            let followers: [FollowRow] = try await client.from("follows").select("follower, followee")
                .eq("followee", value: me).in("follower", values: ids).execute().value
            return (Set(following.map(\.followee)), Set(followers.map(\.follower)))
        }
    }

    public func followingIDs(of me: UUID) async throws -> [UUID] {
        try await socialErrors {
            let rows: [FollowRow] = try await client.from("follows").select("follower, followee")
                .eq("follower", value: me).order("created_at", ascending: false).execute().value
            return rows.map(\.followee)
        }
    }

    public func followerIDs(of me: UUID) async throws -> [UUID] {
        try await socialErrors {
            let rows: [FollowRow] = try await client.from("follows").select("follower, followee")
                .eq("followee", value: me).order("created_at", ascending: false).execute().value
            return rows.map(\.follower)
        }
    }

    public func profiles(ids: [UUID]) async throws -> [PersonRecord] {
        guard !ids.isEmpty else { return [] }
        return try await socialErrors {
            let rows: [PersonRow] = try await client.from("profiles")
                .select("id, username, display_name, is_private")
                .in("id", values: ids).execute().value
            // Keep the order of `ids`, for lists that are sorted by when the follow happened.
            let byID = Dictionary(rows.map { ($0.id, $0.record) }, uniquingKeysWith: { first, _ in first })
            return ids.compactMap { byID[$0] }
        }
    }

    public func follow(_ id: UUID, as me: UUID) async throws {
        try await socialErrors {
            do {
                _ = try await client.from("follows").insert(FollowRow(follower: me, followee: id), returning: .minimal).execute()
            } catch let error as PostgrestError where error.code == "23505" {
                // Already following: the result is what was asked for.
            }
        }
    }

    public func unfollow(_ id: UUID, as me: UUID) async throws {
        try await socialErrors {
            _ = try await client.from("follows").delete().eq("follower", value: me).eq("followee", value: id).execute()
        }
    }

    public func blockedPeople() async throws -> [PersonRecord] {
        try await socialErrors {
            let rows: [BlockedRow] = try await client.rpc("get_blocks").execute().value
            return rows.map { PersonRecord(id: $0.id, username: $0.username, displayName: $0.displayName, isPrivate: false) }
        }
    }

    public func block(_ id: UUID, as me: UUID) async throws {
        try await socialErrors {
            do {
                _ = try await client.from("blocks").insert(BlockRow(blocker: me, blocked: id), returning: .minimal).execute()
            } catch let error as PostgrestError where error.code == "23505" {
                // Already blocked.
            }
        }
    }

    public func unblock(_ id: UUID, as me: UUID) async throws {
        try await socialErrors {
            _ = try await client.from("blocks").delete().eq("blocker", value: me).eq("blocked", value: id).execute()
        }
    }

    public func sharing(of me: UUID) async throws -> SharingChoice {
        try await socialErrors {
            let details: SharingDetails = try await client.rpc("get_profile", params: ["target": me]).single().execute().value
            return SharingChoice(rawValue: details.defaultVisibility ?? "") ?? .private
        }
    }

    public func setSharing(_ choice: SharingChoice, applyToExisting: Bool) async throws -> Int {
        try await socialErrors {
            try await client.rpc("set_sharing", params: SetSharing(newDefault: choice.rawValue, applyToExisting: applyToExisting))
                .execute().value
        }
    }

    public func privacy(of me: UUID) async throws -> PrivacySettings {
        try await socialErrors {
            // The delay is hidden from the table's columns and comes from get_profile, for the owner only.
            let row: PrivateFlag = try await client.from("profiles").select("is_private").eq("id", value: me).single().execute().value
            let details: PostDelayDetails = try await client.rpc("get_profile", params: ["target": me]).single().execute().value
            return PrivacySettings(isPrivate: row.isPrivate, postDelayMinutes: details.postDelayMinutes ?? 0)
        }
    }

    public func setPrivacy(_ settings: PrivacySettings, as me: UUID) async throws {
        try await socialErrors {
            _ = try await client.from("profiles")
                .update(PrivacyUpdate(isPrivate: settings.isPrivate, postDelayMinutes: settings.postDelayMinutes), returning: .minimal)
                .eq("id", value: me)
                .execute()
        }
    }

    private func socialErrors<T: Sendable>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch let error as URLError {
            throw Self.map(error)
        } catch let error as AccountError {
            throw error
        } catch {
            logger.error("Social request failed: \(String(reflecting: type(of: error)), privacy: .public)")
            throw AccountError.unknown
        }
    }
}

private struct PersonRow: Decodable {
    let id: UUID
    let username: String
    let displayName: String?
    let isPrivate: Bool

    var record: PersonRecord { PersonRecord(id: id, username: username, displayName: displayName, isPrivate: isPrivate) }

    private enum CodingKeys: String, CodingKey {
        case id, username
        case displayName = "display_name"
        case isPrivate = "is_private"
    }
}

private struct FollowRow: Codable {
    let follower: UUID
    let followee: UUID
}

private struct BlockRow: Encodable {
    let blocker: UUID
    let blocked: UUID
}

private struct BlockedRow: Decodable {
    let id: UUID
    let username: String
    let displayName: String?

    private enum CodingKeys: String, CodingKey {
        case id, username
        case displayName = "display_name"
    }
}

private struct PrivateFlag: Decodable {
    let isPrivate: Bool

    private enum CodingKeys: String, CodingKey { case isPrivate = "is_private" }
}

private struct PostDelayDetails: Decodable {
    let postDelayMinutes: Int?

    private enum CodingKeys: String, CodingKey { case postDelayMinutes = "post_delay_minutes" }
}

private struct PrivacyUpdate: Encodable {
    let isPrivate: Bool
    let postDelayMinutes: Int

    private enum CodingKeys: String, CodingKey {
        case isPrivate = "is_private"
        case postDelayMinutes = "post_delay_minutes"
    }
}

private struct SharingDetails: Decodable {
    let defaultVisibility: String?

    private enum CodingKeys: String, CodingKey {
        case defaultVisibility = "default_visibility"
    }
}

private struct SetSharing: Encodable {
    let newDefault: String
    let applyToExisting: Bool

    private enum CodingKeys: String, CodingKey {
        case newDefault = "new_default"
        case applyToExisting = "apply_to_existing"
    }
}


// MARK: - Feed

extension SupabaseAccountBackend: FeedBackend {
    public func feed(after cursor: FeedCursor?, pageSize: Int) async throws -> [FeedItem] {
        try await socialErrors {
            try await client.rpc("get_feed", params: FeedParams(cursor: cursor, pageSize: pageSize)).execute().value
        }
    }

    public func personCheckIns(of person: UUID, after cursor: FeedCursor?, pageSize: Int) async throws -> [FeedItem] {
        try await socialErrors {
            try await client.rpc("get_person_checkins", params: PersonParams(target: person, cursor: cursor, pageSize: pageSize))
                .execute().value
        }
    }

    /// An hour is enough to scroll through a page of the feed. Refreshing signs the links again.
    private static let photoLinkLifetime = 3600

    public func photos(for checkIns: [UUID]) async throws -> [FeedPhoto] {
        guard !checkIns.isEmpty else { return [] }
        return try await socialErrors {
            // The database rules decide which rows come back.
            let rows: [PhotoRow] = try await client.from("checkin_photos")
                .select("id, checkin_id, storage_path, width, height, position")
                .in("checkin_id", values: checkIns)
                .order("position", ascending: true)
                .execute().value
            guard !rows.isEmpty else { return [] }
            let signed = try await client.storage.from("photos")
                .createSignedURLs(paths: rows.map(\.storagePath), expiresIn: Self.photoLinkLifetime)
            var urls: [String: URL] = [:]
            for case .success(let path, let url) in signed { urls[path] = url }
            return rows.compactMap { row in
                urls[row.storagePath].map { FeedPhoto(id: row.id, checkInID: row.checkInID, url: $0, width: row.width, height: row.height) }
            }
        }
    }
}

private struct PhotoRow: Decodable {
    let id: UUID
    let checkInID: UUID
    let storagePath: String
    let width: Int?
    let height: Int?

    private enum CodingKeys: String, CodingKey {
        case id, width, height
        case checkInID = "checkin_id"
        case storagePath = "storage_path"
    }
}

private struct PersonParams: Encodable {
    let target: UUID
    let cursor: FeedCursor?
    let pageSize: Int

    private enum CodingKeys: String, CodingKey {
        case target
        case beforeTime = "before_time"
        case beforeID = "before_id"
        case pageSize = "page_size"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(cursor?.time, forKey: .beforeTime)
        try container.encode(cursor?.id, forKey: .beforeID)
        try container.encode(pageSize, forKey: .pageSize)
    }
}

private struct FeedParams: Encodable {
    let cursor: FeedCursor?
    let pageSize: Int

    private enum CodingKeys: String, CodingKey {
        case beforeTime = "before_time"
        case beforeID = "before_id"
        case pageSize = "page_size"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cursor?.time, forKey: .beforeTime)
        try container.encode(cursor?.id, forKey: .beforeID)
        try container.encode(pageSize, forKey: .pageSize)
    }
}


// MARK: - Salutes and comments

extension SupabaseAccountBackend: ReactionBackend {
    public func setSalute(_ on: Bool, checkIn: UUID, as me: UUID) async throws {
        try await socialErrors {
            if on {
                do {
                    _ = try await client.from("salutes").insert(SaluteRow(userID: me, checkInID: checkIn), returning: .minimal).execute()
                } catch let error as PostgrestError where error.code == "23505" {
                    // Already saluted.
                }
            } else {
                _ = try await client.from("salutes").delete().eq("user_id", value: me).eq("checkin_id", value: checkIn).execute()
            }
        }
    }

    public func comments(checkIn: UUID) async throws -> [CheckInComment] {
        try await socialErrors {
            try await client.from("comments")
                .select("id, user_id, body, created_at, profiles(username, display_name)")
                .eq("checkin_id", value: checkIn)
                .order("created_at", ascending: true)
                .execute()
                .value
        }
    }

    public func addComment(_ body: String, checkIn: UUID, as me: UUID) async throws -> CheckInComment {
        try await socialErrors {
            do {
                return try await client.from("comments")
                    .insert(CommentRow(checkInID: checkIn, userID: me, body: body))
                    .select("id, user_id, body, created_at, profiles(username, display_name)")
                    .single()
                    .execute()
                    .value
            } catch let error as PostgrestError where error.code == "23514" {
                // The word filter, or a text outside the allowed length.
                throw AccountError.contentNotAllowed
            }
        }
    }

    public func deleteComment(_ id: UUID) async throws {
        try await socialErrors {
            _ = try await client.from("comments").delete().eq("id", value: id).execute()
        }
    }

    public func report(_ kind: ReportKind, target: UUID, reason: String) async throws -> ReportOutcome {
        try await socialErrors {
            let answer: String = try await client.rpc(
                "report", params: ReportParams(kind: kind.rawValue, target: target.uuidString.lowercased(), reason: reason)
            ).execute().value
            return ReportOutcome(rawValue: answer) ?? .invalidKind
        }
    }
}

private struct ReportParams: Encodable {
    let kind: String
    let target: String
    let reason: String

    private enum CodingKeys: String, CodingKey {
        case kind = "report_kind"
        case target = "report_target"
        case reason = "report_reason"
    }
}

private struct SaluteRow: Encodable {
    let userID: UUID
    let checkInID: UUID

    private enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case checkInID = "checkin_id"
    }
}

private struct CommentRow: Encodable {
    let checkInID: UUID
    let userID: UUID
    let body: String

    private enum CodingKeys: String, CodingKey {
        case body
        case checkInID = "checkin_id"
        case userID = "user_id"
    }
}
