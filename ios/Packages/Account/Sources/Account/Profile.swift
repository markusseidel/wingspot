import Foundation

/// The signed-in user's own profile (`public.profiles`).
public struct Profile: Equatable, Sendable {
    public let id: UUID
    public var username: String
    public var displayName: String?
    /// An airport ID from the reference database.
    public var homeAirportID: Int?

    public init(id: UUID, username: String, displayName: String? = nil, homeAirportID: Int? = nil) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.homeAirportID = homeAirportID
    }

    /// New accounts get a generated `user_…` name from the database until the user picks one.
    public var hasChosenUsername: Bool {
        username.wholeMatch(of: /user_[0-9a-f]{25}/) == nil
    }
}

public enum Username {
    /// Makes typed text match the database format, for example ` Spotter_1 ` becomes `spotter_1`.
    public static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The same rule as the check on `profiles.username`.
    public static func isValid(_ username: String) -> Bool {
        username.wholeMatch(of: /[a-z0-9_]{3,30}/) != nil
    }
}

public enum EmailAddress {
    /// Catches typing mistakes. Only the email itself proves an address works.
    public static func isPlausible(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .wholeMatch(of: /[^@\s]+@[^@\s]+\.[^@\s.]+/) != nil
    }
}
