import OSLog
import Persistence
import ReferenceData
import SwiftData
import SwiftUI
import WingspotCore

private let logger = Logger(subsystem: "app.wingspot.ios", category: "backend")

@main
struct WingspotApp: App {
    private let modelContainer: ModelContainer
    @State private var referenceData: ReferenceDataStore

    init() {
        do {
            modelContainer = try ModelContainer(for: LocalCheckIn.self)
        } catch {
            fatalError("Local check-in storage can't open: \(error)")
        }
        _referenceData = State(initialValue: Self.makeReferenceData())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(referenceData)
                .modelContainer(modelContainer)
                .task { await referenceData.prepare() }
                .task { await loadRemoteConfig() }
                .onOpenURL(perform: handleLink)
        }
    }

    private static var apiClient: APIClient? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "WingspotAPIBaseURL") as? String,
              let baseURL = URL(string: value) else {
            logger.error("WingspotAPIBaseURL is missing from Info.plist")
            return nil
        }
        return APIClient(baseURL: baseURL)
    }

    private static func makeReferenceData() -> ReferenceDataStore {
        #if DEBUG
        // Lets development use a locally built snapshot, which isn't published to hosted.
        if let path = ProcessInfo.processInfo.environment["WINGSPOT_REFDATA_PATH"] {
            return ReferenceDataStore(database: try? ReferenceDatabase(path: path))
        }
        #endif
        let directory = URL.applicationSupportDirectory.appending(path: "ReferenceData")
        return ReferenceDataStore(installer: SnapshotInstaller(directory: directory)) {
            try await apiClient?.refdataManifest()
        }
    }

    private func loadRemoteConfig() async {
        guard let client = Self.apiClient else { return }
        do {
            let config = try await client.config()
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
