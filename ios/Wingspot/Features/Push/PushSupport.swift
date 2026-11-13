import Account
import OSLog
import SwiftUI
import UIKit
import UserNotifications

private let logger = Logger(subsystem: "site.wingspot.ios", category: "push")

/// Where a notification should take the person.
enum PushDestination: Equatable {
    case person(UUID)
    case checkIn(UUID)
}

/// Remembers where a tapped notification points, until a screen has opened it. A tap can arrive before any
/// screen is on show, for example when the app was closed.
@MainActor @Observable
final class PushRouter {
    static let shared = PushRouter()
    var destination: PushDestination?

    /// Reads what the server put into the notification.
    func open(type: String?, checkIn: String?, actor: String?) {
        if type == "follow", let actor, let id = UUID(uuidString: actor) {
            destination = .person(id)
        } else if let checkIn, let id = UUID(uuidString: checkIn) {
            destination = .checkIn(id)
        }
    }
}

/// Receives the push token from the system and the person's taps on notifications.
final class PushAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Set once by the app at start. The token arrives well after that.
    @MainActor static var store: PushStore?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // With previews hidden (Show Previews: When Unlocked or Never), the phone shows this instead of the name
        // and the text, until the iPhone is unlocked.
        let activity = UNNotificationCategory(
            identifier: "WINGSPOT_ACTIVITY", actions: [], intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: String(localized: "New activity on Wingspot"), options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([activity])
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in await Self.store?.didReceive(token: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Never log the error text itself; it can carry identifiers.
        logger.notice("Registering for notifications failed")
    }

    /// While the app is open, notifications still show as a banner.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let type = info["type"] as? String
        let checkIn = info["checkin"] as? String
        let actor = info["actor"] as? String
        await MainActor.run { PushRouter.shared.open(type: type, checkIn: checkIn, actor: actor) }
    }
}

/// The phone's side of notifications.
struct SystemPush: PushSystem {
    func authorization() async -> PushAuthorization {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        default: .allowed
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    @MainActor func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }
}

extension PushStore {
    /// This phone's details for the server. Builds from Xcode use Apple's test push service, all others the real one.
    static func make(backend: PushBackend, userID: @escaping @MainActor () -> UUID?) -> PushStore {
        #if DEBUG
        let environment = DeviceRegistration.Environment.sandbox
        #else
        let environment = DeviceRegistration.Environment.production
        #endif
        return PushStore(
            backend: backend, system: SystemPush(), environment: environment,
            device: {
                (
                    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
                    UIDevice.current.systemVersion,
                    Locale.preferredLanguages.first ?? Locale.current.identifier
                )
            },
            userID: userID
        )
    }
}

/// The notification switches in Settings.
struct NotificationsSection: View {
    @Environment(PushStore.self) private var push

    var body: some View {
        Section {
            switch push.authorization {
            case .notDetermined:
                Button("Turn on notifications") { Task { await push.enable() } }
            case .denied:
                Text("Notifications are off for Wingspot in the system settings.")
                    .foregroundStyle(.secondary)
                Button("Open system settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            case .allowed:
                if let prefs = push.prefs {
                    Toggle("New followers", isOn: binding(prefs, \.newFollowers))
                    Toggle("Salutes", isOn: binding(prefs, \.salutes))
                    Toggle("Comments", isOn: binding(prefs, \.comments))
                    Toggle("Check-ins of people you follow", isOn: binding(prefs, \.followedCheckins))
                    NavigationLink("People you get alerts from") { AlertRulesView() }
                    Button("Hide the text until unlocked") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                } else if push.failure != nil {
                    Label("Couldn't load this. Check your connection.", systemImage: "wifi.slash").foregroundStyle(.secondary)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("A notification shows a name and the start of a comment. To show it only after you unlock your iPhone, open the system settings, tap Notifications, then Show Previews, and choose When Unlocked.")
        }
        .task {
            await push.sync()
            await push.loadPrefs()
        }
    }

    private func binding(_ prefs: NotificationPrefs, _ key: WritableKeyPath<NotificationPrefs, Bool>) -> Binding<Bool> {
        Binding(
            get: { push.prefs?[keyPath: key] ?? prefs[keyPath: key] },
            set: { new in
                var changed = push.prefs ?? prefs
                changed[keyPath: key] = new
                Task { await push.setPrefs(changed) }
            }
        )
    }
}
