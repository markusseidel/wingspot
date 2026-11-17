import Foundation
import Observation

/// Who can see one check-in, apart from the account's sharing choice.
public struct CheckInVisibility: Equatable, Sendable {
    public let level: SharingChoice
    /// True when it was set for this check-in; false when it follows the account's sharing choice.
    public let isCustom: Bool

    public init(level: SharingChoice, isCustom: Bool) {
        self.level = level
        self.isCustom = isCustom
    }
}

public protocol CheckInVisibilityBackend: Sendable {
    /// `get_checkin_visibility`: `nil` when the check-in isn't on the server or isn't yours.
    func checkInVisibility(_ id: UUID) async throws -> CheckInVisibility?
    /// `set_checkin_visibility`. A `nil` choice goes back to the account's sharing choice. Returns the level now, or `nil`
    /// when there is no such check-in of yours.
    func setCheckInVisibility(_ id: UUID, to choice: SharingChoice?) async throws -> SharingChoice?
}

/// Reads and sets who can see one of your own check-ins.
@MainActor
@Observable
public final class CheckInVisibilityStore {
    @ObservationIgnored private let backend: CheckInVisibilityBackend

    public init(backend: CheckInVisibilityBackend) {
        self.backend = backend
    }

    public func visibility(of id: UUID) async throws -> CheckInVisibility? {
        try await backend.checkInVisibility(id)
    }

    /// Sets your own level for the check-in, or `nil` to follow your sharing choice again. Returns what is stored now.
    public func set(_ choice: SharingChoice?, for id: UUID) async throws -> CheckInVisibility? {
        guard try await backend.setCheckInVisibility(id, to: choice) != nil else { return nil }
        return try await backend.checkInVisibility(id)
    }
}

extension UnconfiguredAccountBackend: CheckInVisibilityBackend {
    public func checkInVisibility(_ id: UUID) async throws -> CheckInVisibility? { throw AccountError.notConfigured }
    public func setCheckInVisibility(_ id: UUID, to choice: SharingChoice?) async throws -> SharingChoice? { throw AccountError.notConfigured }
}
