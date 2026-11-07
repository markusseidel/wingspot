import Foundation
import Observation

/// A comment on a check-in.
public struct CheckInComment: Equatable, Sendable, Identifiable, Decodable {
    public let id: UUID
    public let userID: UUID
    public let username: String
    public let displayName: String?
    public let body: String
    public let createdAt: Date

    public init(id: UUID, userID: UUID, username: String, displayName: String? = nil, body: String, createdAt: Date) {
        self.id = id
        self.userID = userID
        self.username = username
        self.displayName = displayName
        self.body = body
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, body, profiles
        case userID = "user_id"
        case createdAt = "created_at"
    }

    private struct Author: Decodable {
        let username: String
        let displayName: String?

        private enum CodingKeys: String, CodingKey {
            case username
            case displayName = "display_name"
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        userID = try c.decode(UUID.self, forKey: .userID)
        body = try c.decode(String.self, forKey: .body)
        let time = try c.decode(String.self, forKey: .createdAt)
        guard let date = FeedItem.parse(time) else {
            throw DecodingError.dataCorruptedError(forKey: .createdAt, in: c, debugDescription: "Not a date: \(time)")
        }
        createdAt = date
        // The author comes embedded from the profiles table.
        let author = try c.decodeIfPresent(Author.self, forKey: .profiles)
        username = author?.username ?? "?"
        displayName = author?.displayName
    }
}

/// Salutes and comments on a check-in. The database rules decide who may do what.
public protocol ReactionBackend: Sendable {
    func setSalute(_ on: Bool, checkIn: UUID, as me: UUID) async throws
    /// Oldest first.
    func comments(checkIn: UUID) async throws -> [CheckInComment]
    func addComment(_ body: String, checkIn: UUID, as me: UUID) async throws -> CheckInComment
    func deleteComment(_ id: UUID) async throws
    func report(_ kind: ReportKind, target: UUID, reason: String) async throws -> ReportOutcome
}

/// The comments under one check-in.
@MainActor
@Observable
public final class CheckInCommentStore {
    public static let maxLength = 2000

    public private(set) var comments: [CheckInComment] = []
    public private(set) var isLoading = false
    public private(set) var hasLoaded = false
    public private(set) var failure: AccountError?
    public private(set) var isSending = false

    private let checkIn: UUID
    private let backend: ReactionBackend
    private let userID: @MainActor () -> UUID?
    private let onCountChange: @MainActor (Int) -> Void

    /// - Parameter onCountChange: told the new number of comments, so the feed card can follow.
    public init(
        checkIn: UUID, backend: ReactionBackend, userID: @escaping @MainActor () -> UUID?,
        onCountChange: @escaping @MainActor (Int) -> Void = { _ in }
    ) {
        self.checkIn = checkIn
        self.backend = backend
        self.userID = userID
        self.onCountChange = onCountChange
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            comments = try await backend.comments(checkIn: checkIn)
            hasLoaded = true
            failure = nil
            onCountChange(comments.count)
        } catch {
            failure = (error as? AccountError) ?? .unknown
        }
    }

    /// Whether `text` can be sent: not empty, and not longer than the database allows.
    public static func isSendable(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= maxLength
    }

    /// - Throws: `AccountError.contentNotAllowed` for a comment the word filter refuses.
    public func send(_ text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isSendable(trimmed), let me = userID() else { throw AccountError.unknown }
        isSending = true
        defer { isSending = false }
        let comment = try await backend.addComment(trimmed, checkIn: checkIn, as: me)
        comments.append(comment)
        onCountChange(comments.count)
    }

    public func delete(_ comment: CheckInComment) async {
        do {
            try await backend.deleteComment(comment.id)
            comments.removeAll { $0.id == comment.id }
            failure = nil
            onCountChange(comments.count)
        } catch {
            failure = (error as? AccountError) ?? .unknown
        }
    }
}
