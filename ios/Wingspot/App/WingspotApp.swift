import Account
import OSLog
import Persistence
import ReferenceData
import SwiftData
import SwiftUI
import WingspotCore

private let logger = Logger(subsystem: "site.wingspot.ios", category: "backend")

@main
struct WingspotApp: App {
    private let modelContainer: ModelContainer
    @State private var referenceData: ReferenceDataStore
    @State private var account = Self.makeAccount()

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
                .environment(account)
                .modelContainer(modelContainer)
                .task { await referenceData.prepare() }
                .task { await loadRemoteConfig() }
                .task { await account.start() }
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

    private static func makeAccount() -> AccountStore {
        var url = Bundle.main.object(forInfoDictionaryKey: "WingspotSupabaseURL") as? String
        var key = Bundle.main.object(forInfoDictionaryKey: "WingspotPublishableKey") as? String
        #if DEBUG
        // Lets development sign in against the local backend.
        let environment = ProcessInfo.processInfo.environment
        url = environment["WINGSPOT_SUPABASE_URL"] ?? url
        key = environment["WINGSPOT_PUBLISHABLE_KEY"] ?? key
        #endif
        guard let url = url.flatMap(URL.init(string:)), let key, !key.isEmpty else {
            logger.notice("No backend key in this build, so sign-in is off")
            return AccountStore(backend: UnconfiguredAccountBackend())
        }
        return AccountStore(backend: SupabaseAccountBackend(url: url, publishableKey: key))
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

    /// Never log the full URL: it can carry sign-in codes.
    private func handleLink(_ url: URL) {
        Task {
            if await !account.handle(url) {
                logger.notice("Ignored an unknown link")
            }
        }
    }
}
