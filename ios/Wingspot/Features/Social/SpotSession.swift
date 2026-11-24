import Account
import Foundation
import SwiftUI

/// A spotting session: an airport visit at a spotting location, during which new sightings are linked to the visit.
/// It lasts until the person ends it, or twelve hours.
@MainActor
@Observable
final class SpotSessionStore {
    struct Session: Codable, Equatable {
        let visitID: UUID
        let spotID: Int
        let spotName: String
        let airportID: Int
        let code: String
        let startedAt: Date
        /// For a backdated visit: the day (and time) of the visit, which the sightings of the session start with. Nil: they happen now.
        /// New optional fields like these read an older saved session without a migration step.
        var visitMoment: Date?
        var visitTimeKnown: Bool?
    }

    static let lifetime: TimeInterval = 12 * 3600
    private static let key = "spotSession"

    private let defaults: UserDefaults
    private let now: () -> Date
    private(set) var current: Session?

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        current = Self.load(defaults, now: now())
    }

    /// The running session, unless it ran out.
    var session: Session? {
        guard let current, now().timeIntervalSince(current.startedAt) < Self.lifetime else { return nil }
        return current
    }

    func start(_ session: Session) {
        current = session
        if let data = try? JSONEncoder().encode(session) { defaults.set(data, forKey: Self.key) }
    }

    func end() {
        current = nil
        defaults.removeObject(forKey: Self.key)
    }

    private static func load(_ defaults: UserDefaults, now: Date) -> Session? {
        guard let data = defaults.data(forKey: key), let session = try? JSONDecoder().decode(Session.self, from: data),
              now.timeIntervalSince(session.startedAt) < lifetime else { return nil }
        return session
    }
}

/// Says that a session is running and lets the person end it.
struct SpotSessionRow: View {
    @Environment(SpotSessionStore.self) private var sessions

    var body: some View {
        if let session = sessions.session {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Session at \(session.spotName)")
                        Text("Aircraft you spot now are added to it.").font(.footnote).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "binoculars.fill").foregroundStyle(.tint)
                }
                Button("End session", role: .destructive) { sessions.end() }
            }
        }
    }
}
