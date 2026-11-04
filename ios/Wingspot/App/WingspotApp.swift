import OSLog
import SwiftUI
import WingspotCore

private let logger = Logger(subsystem: "app.wingspot.ios", category: "backend")

@main
struct WingspotApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .task { await loadRemoteConfig() }
                .onOpenURL(perform: handleLink)
        }
    }

    private func loadRemoteConfig() async {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "WingspotAPIBaseURL") as? String,
              let baseURL = URL(string: value) else {
            logger.error("WingspotAPIBaseURL is missing from Info.plist")
            return
        }
        do {
            let config = try await APIClient(baseURL: baseURL).config()
            logger.info("Remote config loaded, minimum iOS version \(config.minimumVersion.ios, privacy: .public)")
        } catch {
            logger.error("Remote config failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Sign-in isn't built yet, so email links only open the app. Never log the full URL:
    /// it can carry sign-in tokens.
    private func handleLink(_ url: URL) {
        guard url.scheme == "wingspot", url.host == "auth-callback" else {
            logger.notice("Ignored an unknown link")
            return
        }
        logger.info("Opened from an auth link")
    }
}
