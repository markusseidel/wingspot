import Foundation
import Supabase

/// Whose invite code it is, or who the server follows for you.
public struct InvitePerson: Identifiable, Equatable, Sendable, Decodable {
    public let id: UUID
    public let username: String
    public let displayName: String?

    public init(id: UUID, username: String, displayName: String?) {
        self.id = id
        self.username = username
        self.displayName = displayName
    }

    public var name: String {
        if let displayName, !displayName.trimmingCharacters(in: .whitespaces).isEmpty { return displayName }
        return username
    }

    private enum CodingKeys: String, CodingKey {
        case id, username
        case displayName = "display_name"
    }
}

/// Someone you may know: followed by people you follow, or tagged with you.
public struct PersonSuggestion: Identifiable, Equatable, Sendable, Decodable {
    public let userID: UUID
    public let username: String
    public let displayName: String?
    /// `mutual` or `tagged`.
    public let reason: String
    public let mutual: Int
    public var id: UUID { userID }

    public init(userID: UUID, username: String, displayName: String?, reason: String, mutual: Int) {
        self.userID = userID
        self.username = username
        self.displayName = displayName
        self.reason = reason
        self.mutual = mutual
    }

    public var name: String {
        if let displayName, !displayName.trimmingCharacters(in: .whitespaces).isEmpty { return displayName }
        return username
    }

    private enum CodingKeys: String, CodingKey {
        case username, reason, mutual
        case userID = "user_id"
        case displayName = "display_name"
    }
}

/// The personal invite code, following by code, and the people you may know.
public protocol InviteBackend: Sendable {
    func myInviteCode() async throws -> String
    func resetInviteCode() async throws -> String
    /// Who owns the code. `nil` for an unknown code, a blocked person or yourself.
    func inviteOwner(code: String) async throws -> InvitePerson?
    /// Follows the owner of the code and returns them. `nil` for an unknown code.
    func followByCode(_ code: String) async throws -> InvitePerson?
    func suggestions() async throws -> [PersonSuggestion]
    func allowsSuggestions(of me: UUID) async throws -> Bool
    func setAllowsSuggestions(_ allowed: Bool, as me: UUID) async throws
}

extension SupabaseAccountBackend: InviteBackend {
    public func myInviteCode() async throws -> String {
        try await mappingErrors { try await client.rpc("get_my_invite_code").execute().value }
    }

    public func resetInviteCode() async throws -> String {
        try await mappingErrors { try await client.rpc("reset_my_invite_code").execute().value }
    }

    public func inviteOwner(code: String) async throws -> InvitePerson? {
        let rows: [InvitePerson] = try await mappingErrors {
            try await client.rpc("invite_owner", params: ["p_code": code]).execute().value
        }
        return rows.first
    }

    public func followByCode(_ code: String) async throws -> InvitePerson? {
        let rows: [InvitePerson] = try await mappingErrors {
            try await client.rpc("follow_by_code", params: ["p_code": code]).execute().value
        }
        return rows.first
    }

    public func suggestions() async throws -> [PersonSuggestion] {
        try await mappingErrors { try await client.rpc("people_you_may_know").execute().value }
    }

    public func allowsSuggestions(of me: UUID) async throws -> Bool {
        let row: AllowRow = try await mappingErrors {
            try await client.from("profiles").select("allow_suggestions").eq("id", value: me).single().execute().value
        }
        return row.allowed
    }

    public func setAllowsSuggestions(_ allowed: Bool, as me: UUID) async throws {
        try await mappingErrors {
            _ = try await client.from("profiles").update(AllowUpdate(allowed: allowed), returning: .minimal).eq("id", value: me).execute()
        }
    }
}

private struct AllowRow: Decodable {
    let allowed: Bool
    private enum CodingKeys: String, CodingKey { case allowed = "allow_suggestions" }
}

private struct AllowUpdate: Encodable {
    let allowed: Bool
    private enum CodingKeys: String, CodingKey { case allowed = "allow_suggestions" }
}

extension UnconfiguredAccountBackend: InviteBackend {
    public func myInviteCode() async throws -> String { throw AccountError.notConfigured }
    public func resetInviteCode() async throws -> String { throw AccountError.notConfigured }
    public func inviteOwner(code: String) async throws -> InvitePerson? { throw AccountError.notConfigured }
    public func followByCode(_ code: String) async throws -> InvitePerson? { throw AccountError.notConfigured }
    public func suggestions() async throws -> [PersonSuggestion] { throw AccountError.notConfigured }
    public func allowsSuggestions(of me: UUID) async throws -> Bool { throw AccountError.notConfigured }
    public func setAllowsSuggestions(_ allowed: Bool, as me: UUID) async throws { throw AccountError.notConfigured }
}

/// The invite link: `wingspot://invite/CODE`.
public enum InviteLink {
    public static let alphabet = Set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    public static func url(for code: String) -> URL? { URL(string: "wingspot://invite/\(code)") }

    /// The code in an invite link, or `nil` if this is not one.
    public static func code(in url: URL) -> String? {
        guard url.scheme == "wingspot", url.host == "invite" else { return nil }
        return clean(url.lastPathComponent)
    }

    /// A typed or pasted code made tidy: trimmed, upper case, and only if it has the right shape.
    public static func clean(_ text: String) -> String? {
        let code = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 8, code.allSatisfy({ alphabet.contains($0) }) else { return nil }
        return code
    }
}
