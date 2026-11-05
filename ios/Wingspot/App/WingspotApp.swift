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
    @State private var account: AccountStore
    @State private var sync: CheckInSyncCoordinator
    @State private var badges: BadgeStore
    @Environment(\.scenePhase) private var scenePhase
    private let network = NetworkMonitor()

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: LocalCheckIn.self, BadgeAck.self, BadgeAccount.self)
        } catch {
            fatalError("Local check-in storage can't open: \(error)")
        }
        modelContainer = container
        _referenceData = State(initialValue: Self.makeReferenceData())

        let account = Self.makeAccount()
        _account = State(initialValue: account)
        let uploader = APICheckInUploader(
            client: Self.apiClient,
            accessToken: { await account.accessToken() }
        )
        let badgeStore = BadgeStore(
            context: container.mainContext,
            source: APIProgressSource(client: Self.apiClient, accessToken: { await account.accessToken() })
        )
        _badges = State(initialValue: badgeStore)
        _sync = State(initialValue: CheckInSyncCoordinator(
            outbox: CheckInOutbox(context: container.mainContext, uploader: uploader),
            userID: { account.userID },
            // After a run, with or without uploads, the server may have unlocked something.
            afterRun: { Task { await badgeStore.refresh() } }
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(referenceData)
                .environment(account)
                .environment(sync)
                .environment(badges)
                .modelContainer(modelContainer)
                .task { await referenceData.prepare() }
                .task { await loadRemoteConfig() }
                .task {
                    await account.start()
                    badges.begin(userID: account.userID)
                    sync.requestSync()
                }
                .task { network.start { Task { @MainActor in sync.requestSync() } } }
                // After signing in or out, and each time the app comes to the foreground.
                .onChange(of: account.userID) {
                    badges.begin(userID: account.userID)
                    sync.requestSync()
                }
                .onChange(of: scenePhase) { if scenePhase == .active { sync.requestSync() } }
                .onOpenURL(perform: handleLink)
        }
    }

    private static var apiClient: APIClient? {
        var value = Bundle.main.object(forInfoDictionaryKey: "WingspotAPIBaseURL") as? String
        #if DEBUG
        // Lets development talk to the local backend.
        value = ProcessInfo.processInfo.environment["WINGSPOT_API_BASE_URL"] ?? value
        #endif
        guard let value, let baseURL = URL(string: value) else {
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
