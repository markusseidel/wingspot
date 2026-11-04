import Foundation
import Observation
import OSLog
import WingspotCore

private let logger = Logger(subsystem: "site.wingspot.ios", category: "refdata")

/// Keeps the on-device reference database current. A failed update leaves the installed snapshot in use.
@MainActor @Observable
public final class ReferenceDataStore {
    public typealias ManifestSource = @Sendable () async throws -> RefdataManifest?

    public private(set) var database: ReferenceDatabase?
    public private(set) var isUpdating = false

    @ObservationIgnored private let installer: SnapshotInstaller?
    @ObservationIgnored private let manifest: ManifestSource

    public init(installer: SnapshotInstaller, manifest: @escaping ManifestSource) {
        self.installer = installer
        self.manifest = manifest
    }

    /// Uses a fixed database and never downloads, for development and previews.
    public init(database: ReferenceDatabase?) {
        self.database = database
        self.installer = nil
        self.manifest = { nil }
    }

    /// Opens the installed snapshot straight away, so search works offline, then looks for a newer one.
    public func prepare() async {
        guard let installer else { return }
        if database == nil { database = installer.installedDatabase() }

        isUpdating = true
        defer { isUpdating = false }
        do {
            guard let current = try await manifest(), current.dataVersion != database?.dataVersion else { return }
            database = try await installer.install(current)
            logger.info("Installed reference data \(current.dataVersion, privacy: .public)")
        } catch {
            logger.error("Reference data update failed: \(String(describing: error), privacy: .public)")
        }
    }
}
