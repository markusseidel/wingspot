import Foundation
import WingspotCore

/// KML files that were shared or opened into Wingspot from another app (the share sheet, Files, Mail, the Flightradar24 app), waiting for
/// the Flown form to read them. Like `QuickActionRouter`, it waits because the files can arrive before any screen is on show, and several
/// files shared at once arrive one after the other.
@MainActor @Observable
final class KmlInbox {
    static let shared = KmlInbox()
    var pending: [URL] = []

    /// Keeps a KML file for the Flown form. Returns `false` for any other file.
    @discardableResult
    func offer(_ url: URL) -> Bool {
        guard KmlFile.isKml(url) else { return false }
        pending.append(url)
        return true
    }

    /// Everything that arrived, and empties the inbox.
    func takeAll() -> [URL] {
        defer { pending = [] }
        return pending
    }
}
