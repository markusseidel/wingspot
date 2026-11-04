import CryptoKit
import Foundation
import WingspotCore

/// Downloads a reference snapshot, checks it, and only then replaces the installed one.
public struct SnapshotInstaller: Sendable {
    public typealias Download = @Sendable (URL) async throws -> URL

    private let directory: URL
    private let download: Download

    public init(directory: URL, download: @escaping Download = SnapshotInstaller.urlSessionDownload) {
        self.directory = directory
        self.download = download
    }

    private var databaseURL: URL { directory.appending(path: "refdata.sqlite") }

    /// The installed snapshot, or `nil` if there is none this code can open.
    public func installedDatabase() -> ReferenceDatabase? {
        try? ReferenceDatabase(path: databaseURL.path)
    }

    public func install(_ manifest: RefdataManifest) async throws -> ReferenceDatabase {
        guard manifest.schemaVersion == ReferenceDatabase.supportedSchemaVersion else {
            throw ReferenceDataError.unsupportedSchema(manifest.schemaVersion)
        }
        guard manifest.url.scheme == "https" else { throw ReferenceDataError.insecureURL }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let downloaded = try await download(manifest.url)
        defer { try? fileManager.removeItem(at: downloaded) }

        let data = try Data(contentsOf: downloaded, options: .mappedIfSafe)
        guard data.count == manifest.sizeBytes else { throw ReferenceDataError.sizeMismatch }
        let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard checksum == manifest.sha256 else { throw ReferenceDataError.checksumMismatch }

        // A separate file, so a bad snapshot never replaces a working one.
        let candidate = directory.appending(path: "refdata-\(UUID().uuidString).sqlite")
        try data.write(to: candidate, options: .atomic)
        defer { try? fileManager.removeItem(at: candidate) }
        _ = try ReferenceDatabase(path: candidate.path)

        if fileManager.fileExists(atPath: databaseURL.path) {
            _ = try fileManager.replaceItemAt(databaseURL, withItemAt: candidate)
        } else {
            try fileManager.moveItem(at: candidate, to: databaseURL)
        }
        var installed = databaseURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try installed.setResourceValues(values)
        return try ReferenceDatabase(path: installed.path)
    }

    public static let urlSessionDownload: Download = { url in
        let (file, response) = try await URLSession.shared.download(from: url)
        if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
            try? FileManager.default.removeItem(at: file)
            throw ReferenceDataError.downloadFailed(status)
        }
        return file
    }
}
