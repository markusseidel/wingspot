import SwiftUI
import UIKit
import WingspotCore

/// Remembers which shortcut of the app icon was chosen until the main screen has opened it (#349). It can arrive before any screen is on
/// show (the app was closed), or while onboarding is up, so it waits, like a tapped notification does in `PushRouter`.
@MainActor @Observable
final class QuickActionRouter {
    static let shared = QuickActionRouter()
    var pending: QuickAction?

    /// Reads the type of a chosen shortcut. Anything that is not ours is ignored.
    @discardableResult
    func handle(type: String) -> Bool {
        guard let action = QuickAction(type: type) else { return false }
        pending = action
        return true
    }

    /// The check-in form a shortcut opens.
    static func kind(for action: QuickAction) -> CheckInKind {
        switch action {
        case .spotted, .session: .spotted
        case .flown: .flown
        case .airport: .airport
        }
    }

    /// The entry that is only there while a spotting session runs: it is added to the three fixed ones, and taken away again when the
    /// session ends or runs out.
    static func showSession(_ session: SpotSessionStore.Session?) {
        UIApplication.shared.shortcutItems = session.map { session in
            [UIApplicationShortcutItem(
                type: QuickAction.session.type, localizedTitle: String(localized: "Session at \(session.spotName)"),
                localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: "binoculars.fill")
            )]
        } ?? []
    }
}

/// Hears a shortcut chosen while the app is running. A shortcut that starts the app is read in the app delegate, which gets the
/// connection options first.
final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        await MainActor.run { QuickActionRouter.shared.handle(type: shortcutItem.type) }
    }
}
