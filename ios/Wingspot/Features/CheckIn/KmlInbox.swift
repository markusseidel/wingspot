import Foundation
import WingspotCore

/// A KML file that was shared or opened into Wingspot from another app (the share sheet, Files, Mail, the Flightradar24 app), waiting for
/// the Flown form to read it. Like `QuickActionRouter`, it waits because the file can arrive before any screen is on show.
@MainActor @Observable
final class KmlInbox {
    static let shared = KmlInbox()
    var pending: URL?

    /// Keeps a KML file for the Flown form. Returns `false` for any other file.
    @discardableResult
    func offer(_ url: URL) -> Bool {
        guard KmlFile.isKml(url) else { return false }
        pending = url
        return true
    }
}
