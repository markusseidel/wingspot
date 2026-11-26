import Foundation
import Observation

/// The rules version and age confirmation kept with the account (docs/MINIMUM-AGE-PLAN.md).
public protocol TermsBackend: Sendable {
    /// The version the account agreed to; 0 when none.
    func myTermsVersion() async throws -> Int
    /// Records that the signed-in person agreed to `version`; from version 2 this includes "I am 16 or older".
    func acceptTerms(version: Int) async throws
}

/// Whether this person has accepted the community rules. Kept on the device per account, so the app starts offline, and with the
/// account on the server, so a second phone or a reinstall doesn't ask again. Raise `currentVersion` when the rules change, and
/// everyone is asked again.
@MainActor
@Observable
public final class TermsStore {
    /// Version 2 added "I am 16 or older".
    public static let currentVersion = 2

    private let defaults: UserDefaults
    private let userID: @MainActor () -> UUID?
    private let backend: TermsBackend?
    /// Bumped on every change, so views that read `hasAccepted` update.
    private var changes = 0

    public init(defaults: UserDefaults = .standard, backend: TermsBackend? = nil, userID: @escaping @MainActor () -> UUID?) {
        self.defaults = defaults
        self.backend = backend
        self.userID = userID
    }

    private func key(_ id: UUID) -> String { "termsAcceptedVersion.\(id.uuidString)" }
    /// Set while an agreement made on this phone has not reached the server yet.
    private func pendingKey(_ id: UUID) -> String { "termsUploadPending.\(id.uuidString)" }

    /// Set when this build is older than the server's minimum (docs/MINIMUM-AGE-PLAN.md 4a). The social parts then stay closed,
    /// like before agreeing, and the rules screen asks for an update instead.
    public var updateRequired = false

    /// Whether the social parts are open: the signed-in person agreed to the current rules and this build is not too old.
    /// Nobody signed in counts as not accepted.
    public var hasAccepted: Bool {
        _ = changes
        guard !updateRequired, let id = userID() else { return false }
        return defaults.integer(forKey: key(id)) >= Self.currentVersion
    }

    /// Agrees for the signed-in person: on this phone at once, on the server as soon as it can be reached.
    public func accept() {
        guard let id = userID() else { return }
        defaults.set(Self.currentVersion, forKey: key(id))
        defaults.set(true, forKey: pendingKey(id))
        changes += 1
        Task { await sync() }
    }

    /// Brings phone and server together: an agreement from another phone is taken over, one made here that didn't reach the server
    /// is sent again. Call it after signing in and when the app starts. Failures are left for the next time.
    public func sync() async {
        guard let backend, let id = userID() else { return }
        if defaults.bool(forKey: pendingKey(id)) {
            let version = defaults.integer(forKey: key(id))
            guard (try? await backend.acceptTerms(version: version)) != nil else { return }
            if userID() == id { defaults.removeObject(forKey: pendingKey(id)) }
            return
        }
        guard !hasAccepted, let stored = try? await backend.myTermsVersion(), userID() == id else { return }
        if stored > defaults.integer(forKey: key(id)) {
            defaults.set(stored, forKey: key(id))
            changes += 1
        }
    }
}

extension SupabaseAccountBackend: TermsBackend {
    public func myTermsVersion() async throws -> Int {
        let rows: [TermsRow] = try await mappingErrors { try await client.rpc("get_my_terms").execute().value }
        return rows.first?.version ?? 0
    }

    public func acceptTerms(version: Int) async throws {
        try await mappingErrors { _ = try await client.rpc("accept_terms", params: ["p_version": version]).execute() }
    }
}

private struct TermsRow: Decodable {
    let version: Int
    private enum CodingKeys: String, CodingKey { case version = "terms_version" }
}

extension UnconfiguredAccountBackend: TermsBackend {
    public func myTermsVersion() async throws -> Int { throw AccountError.notConfigured }
    public func acceptTerms(version: Int) async throws { throw AccountError.notConfigured }
}
