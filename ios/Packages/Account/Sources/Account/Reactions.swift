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

/// A person named in a comment with @username.
public struct CommentMention: Equatable, Sendable, Decodable {
    public let id: UUID
    public let username: String

    public init(id: UUID, username: String) {
        self.id = id
        self.username = username
    }
}

/// What a comment has besides its text: salutes and the people it mentions (`get_comment_extras`).
public struct CommentExtra: Equatable, Sendable, Decodable {
    public var salutes: Int
    public var saluted: Bool
    public let mentions: [CommentMention]

    public init(salutes: Int = 0, saluted: Bool = false, mentions: [CommentMention] = []) {
        self.salutes = salutes
        self.saluted = saluted
        self.mentions = mentions
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
    /// The salutes and mentions of the comments under a check-in, by comment id.
    func commentExtras(checkIn: UUID) async throws -> [UUID: CommentExtra]
    func setCommentSalute(_ on: Bool, comment: UUID) async throws
}

extension ReactionBackend {
    public func commentExtras(checkIn: UUID) async throws -> [UUID: CommentExtra] { [:] }
    public func setCommentSalute(_ on: Bool, comment: UUID) async throws {}
}

/// The comments under one check-in.
@MainActor
@Observable
public final class CheckInCommentStore {
    public static let maxLength = 2000

    public private(set) var comments: [CheckInComment] = []
    /// Salutes and mentions by comment id. A comment without an entry has none.
    public private(set) var extras: [UUID: CommentExtra] = [:]
    public private(set) var isLoading = false
    public private(set) var hasLoaded = false
    public private(set) var failure: AccountError?
    public private(set) var isSending = false

    private let checkIn: UUID
    private let backend: ReactionBackend
    private let userID: @MainActor () -> UUID?
    private let onCountChange: @MainActor (Int) -> Void
    private let onPosted: @MainActor () -> Void

    /// - Parameter onCountChange: told the new number of comments, so the feed card can follow.
    public init(
        checkIn: UUID, backend: ReactionBackend, userID: @escaping @MainActor () -> UUID?,
        onCountChange: @escaping @MainActor (Int) -> Void = { _ in },
        onPosted: @escaping @MainActor () -> Void = {}
    ) {
        self.checkIn = checkIn
        self.backend = backend
        self.userID = userID
        self.onCountChange = onCountChange
        self.onPosted = onPosted
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            comments = try await backend.comments(checkIn: checkIn)
            hasLoaded = true
            failure = nil
            onCountChange(comments.count)
            // The extras are a bonus: the comments show without them.
            extras = (try? await backend.commentExtras(checkIn: checkIn)) ?? extras
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
        onPosted()
        // The server reads the @names of the new comment; ask for them so they are links at once.
        extras = (try? await backend.commentExtras(checkIn: checkIn)) ?? extras
    }

    /// Salutes or un-salutes a comment at once and tells the server; goes back if that fails.
    public func toggleSalute(_ comment: CheckInComment) async {
        let before = extras[comment.id] ?? CommentExtra()
        var after = before
        after.saluted.toggle()
        after.salutes = max(0, before.salutes + (after.saluted ? 1 : -1))
        extras[comment.id] = after
        do {
            try await backend.setCommentSalute(after.saluted, comment: comment.id)
        } catch {
            extras[comment.id] = before
        }
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
