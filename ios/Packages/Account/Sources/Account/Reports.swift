import Foundation
import Observation

/// What can be reported. The words match the `report` function on the server.
public enum ReportKind: String, Sendable, CaseIterable {
    case user, checkin, comment, photo
}

/// Why someone is reported. The server stores the reason as free text, so this becomes its first words.
public enum ReportReason: String, Sendable, CaseIterable, Identifiable {
    case spam, offensive, privacy, other
    public var id: String { rawValue }
}

public enum ReportOutcome: String, Sendable {
    case reported
    /// The target doesn't exist, or the caller can't see it any more.
    case unknownTarget = "unknown_target"
    /// 20 reports in an hour.
    case tooMany = "too_many"
    case invalidKind = "invalid_kind"
}

/// Sends reports about users, check-ins, comments and photos.
@MainActor
@Observable
public final class Reporter {
    private let backend: ReactionBackend

    public init(backend: ReactionBackend) {
        self.backend = backend
    }

    /// - Parameter details: what the reporter wrote, if anything.
    /// - Throws: `AccountError.tooManyRequests` after 20 reports in an hour, `.unknown` if the target is gone.
    public func report(_ kind: ReportKind, target: UUID, reason: ReportReason, details: String) async throws {
        let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = trimmed.isEmpty ? reason.rawValue : "\(reason.rawValue): \(trimmed)"
        switch try await backend.report(kind, target: target, reason: String(text.prefix(1000))) {
        case .reported: return
        case .tooMany: throw AccountError.tooManyRequests
        case .unknownTarget, .invalidKind: throw AccountError.unknown
        }
    }
}
