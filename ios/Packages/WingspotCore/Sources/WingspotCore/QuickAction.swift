import Foundation

/// What a long press on the app icon can open (#349). The `type` strings are the ones in `Info.plist` (`UIApplicationShortcutItems`)
/// and the one of the dynamic session entry.
public enum QuickAction: String, CaseIterable, Sendable {
    case spotted, flown, airport
    /// The entry that is only there while a spotting session runs. It opens the sighting form, which joins the session.
    case session

    public static let typePrefix = "site.wingspot.quick."

    public var type: String { Self.typePrefix + rawValue }

    /// `nil` for anything that is not one of ours.
    public init?(type: String) {
        guard type.hasPrefix(Self.typePrefix), let action = Self(rawValue: String(type.dropFirst(Self.typePrefix.count))) else { return nil }
        self = action
    }
}
