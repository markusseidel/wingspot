import Foundation
import Observation

/// Whether this person has accepted the community rules, kept on the device per account.
/// Raise `currentVersion` when the rules change, and everyone is asked again.
@MainActor
@Observable
public final class TermsStore {
    public static let currentVersion = 1

    private let defaults: UserDefaults
    private let userID: @MainActor () -> UUID?
    /// Bumped on every acceptance, so views that read `hasAccepted` update.
    private var changes = 0

    public init(defaults: UserDefaults = .standard, userID: @escaping @MainActor () -> UUID?) {
        self.defaults = defaults
        self.userID = userID
    }

    private func key(_ id: UUID) -> String { "termsAcceptedVersion.\(id.uuidString)" }

    /// Nobody signed in counts as not accepted.
    public var hasAccepted: Bool {
        _ = changes
        guard let id = userID() else { return false }
        return defaults.integer(forKey: key(id)) >= Self.currentVersion
    }

    public func accept() {
        guard let id = userID() else { return }
        defaults.set(Self.currentVersion, forKey: key(id))
        changes += 1
    }
}
