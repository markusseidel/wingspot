import CryptoKit
import Foundation
import Testing
import WingspotCore
@testable import ReferenceData

private struct Sample {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let file: URL
    let data: Data

    init(dataVersion: String = "test-1") throws {
        file = try Fixture.makeDatabase(dataVersion: dataVersion)
        data = try Data(contentsOf: file)
    }

    func manifest(
        schema: Int = ReferenceDatabase.supportedSchemaVersion, url: String = "https://example.com/refdata.sqlite",
        sha: String? = nil, size: Int? = nil, version: String = "test-1"
    ) -> RefdataManifest {
        RefdataManifest(
            schemaVersion: schema, dataVersion: version, url: URL(string: url)!,
            sha256: sha ?? SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            sizeBytes: size ?? data.count
        )
    }

    /// Hands out a copy, because the installer deletes what it downloads.
    func installer() -> SnapshotInstaller {
        let source = data
        return SnapshotInstaller(directory: directory) { _ in
            let copy = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try source.write(to: copy)
            return copy
        }
    }
}

@Test func installsAValidSnapshot() async throws {
    let sample = try Sample()
    let database = try await sample.installer().install(sample.manifest())
    #expect(database.dataVersion == "test-1")
    #expect(sample.installer().installedDatabase()?.dataVersion == "test-1")
}

@Test func rejectsAWrongChecksum() async throws {
    let sample = try Sample()
    await #expect(throws: ReferenceDataError.checksumMismatch) {
        try await sample.installer().install(sample.manifest(sha: String(repeating: "0", count: 64)))
    }
    #expect(sample.installer().installedDatabase() == nil)
}

@Test func rejectsAWrongSize() async throws {
    let sample = try Sample()
    await #expect(throws: ReferenceDataError.sizeMismatch) {
        try await sample.installer().install(sample.manifest(size: 1))
    }
}

@Test func rejectsAnUnsupportedSchemaBeforeDownloading() async throws {
    let sample = try Sample()
    await #expect(throws: ReferenceDataError.unsupportedSchema(99)) {
        try await sample.installer().install(sample.manifest(schema: 99))
    }
}

@Test func rejectsPlainHTTP() async throws {
    let sample = try Sample()
    await #expect(throws: ReferenceDataError.insecureURL) {
        try await sample.installer().install(sample.manifest(url: "http://example.com/refdata.sqlite"))
    }
}

@Test func aBadUpdateKeepsTheInstalledSnapshot() async throws {
    let sample = try Sample()
    _ = try await sample.installer().install(sample.manifest())
    await #expect(throws: ReferenceDataError.checksumMismatch) {
        try await sample.installer().install(sample.manifest(sha: String(repeating: "0", count: 64), version: "test-2"))
    }
    #expect(sample.installer().installedDatabase()?.dataVersion == "test-1")
}

@Test func aNewSnapshotReplacesTheOldOne() async throws {
    let first = try Sample(dataVersion: "test-1")
    _ = try await first.installer().install(first.manifest())

    let newer = try Sample(dataVersion: "test-2")
    let source = newer.data
    let installer = SnapshotInstaller(directory: first.directory) { _ in
        let copy = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try source.write(to: copy)
        return copy
    }
    let database = try await installer.install(newer.manifest(version: "test-2"))
    #expect(database.dataVersion == "test-2")
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: first.directory.path)
    #expect(leftovers == ["refdata.sqlite"])
}

@MainActor @Test func theStoreSkipsADownloadWhenAlreadyCurrent() async throws {
    let sample = try Sample()
    _ = try await sample.installer().install(sample.manifest())
    let manifest = sample.manifest()
    let installer = SnapshotInstaller(directory: sample.directory) { _ in
        Issue.record("should not download")
        throw ReferenceDataError.downloadFailed(0)
    }
    let store = ReferenceDataStore(installer: installer, manifest: { manifest })
    await store.prepare()
    #expect(store.database?.dataVersion == "test-1")
    #expect(store.isUpdating == false)
}

@MainActor @Test func theStoreKeepsWorkingOffline() async throws {
    let sample = try Sample()
    _ = try await sample.installer().install(sample.manifest())
    let store = ReferenceDataStore(installer: sample.installer(), manifest: { throw URLError(.notConnectedToInternet) })
    await store.prepare()
    #expect(store.database?.dataVersion == "test-1")
}
