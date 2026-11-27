import Foundation
import SwiftData
import Testing
import WingspotCore
@testable import Persistence

@MainActor
private func makeContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: LocalCheckIn.self, LocalPhoto.self, BadgeAck.self, BadgeAccount.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return ModelContext(container)
}

private func temporaryDirectory(_ name: String) -> URL {
    FileManager.default.temporaryDirectory.appending(path: "\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
}

private let route = [GeoCoordinate(latitude: 51.28, longitude: 6.76), GeoCoordinate(latitude: 52.36, longitude: 13.5)]

private final class Counter: @unchecked Sendable {
    var value = 0
}

@MainActor
private func pendingCheckIn(_ id: UUID = UUID()) -> LocalCheckIn {
    LocalCheckIn(
        id: id, kind: "spotted", registration: "D-AIXA", typeICAO: nil, typeName: nil, airportID: nil, airportCode: nil,
        latitude: nil, longitude: nil, occurredAt: .now, syncState: .pending, ownerID: nil
    )
}

@MainActor @Test func theFingerprintChangesOnlyWithWhatIsInTheBackup() throws {
    let context = try makeContext()
    let tracks = FlightTrackFiles(directory: temporaryDirectory("tracks"))
    let service = BackupService(context: context, tracks: tracks)
    let empty = try service.snapshot(app: "test")
    #expect(empty.isEmpty)

    let synced = pendingCheckIn()
    synced.syncState = SyncState.synced.rawValue
    context.insert(synced)
    try context.save()
    #expect(try service.snapshot(app: "test").fingerprint == empty.fingerprint)

    let pending = pendingCheckIn()
    context.insert(pending)
    try context.save()
    let withCheckIn = try service.snapshot(app: "test")
    #expect(!withCheckIn.isEmpty && withCheckIn.fingerprint != empty.fingerprint)
    #expect(try service.snapshot(app: "test", now: .now.addingTimeInterval(60)).fingerprint == withCheckIn.fingerprint)

    pending.seat = "12A"
    try context.save()
    let edited = try service.snapshot(app: "test")
    #expect(edited.fingerprint != withCheckIn.fingerprint)

    try tracks.save(route, for: synced.id)
    let withRoute = try service.snapshot(app: "test")
    #expect(withRoute.fingerprint != edited.fingerprint)
    #expect(withRoute.document().routes.features.count == 1)

    pending.syncState = SyncState.synced.rawValue
    try context.save()
    #expect(try service.snapshot(app: "test").fingerprint != withRoute.fingerprint)
}

@Test func theFolderKeepsTheLatestAndThePreviousFile() throws {
    let folder = BackupFolder(directory: temporaryDirectory("backup"), coordinated: false)
    try folder.write(Data("one".utf8), device: "iPhone A")
    try folder.write(Data("two".utf8), device: "iPhone A")
    try folder.write(Data("three".utf8), device: "iPhone A")
    try folder.write(Data("other".utf8), device: "iPhone/B")

    let latest = folder.directory.appending(path: "Wingspot-backup-iPhone A.wingspotbackup")
    let previous = folder.directory.appending(path: "Wingspot-backup-iPhone A-previous.wingspotbackup")
    #expect(try Data(contentsOf: latest) == Data("three".utf8))
    #expect(try Data(contentsOf: previous) == Data("two".utf8))

    let files = folder.backups()
    #expect(files.count == 3)
    #expect(Set(files.filter { !$0.isPrevious }.map(\.device)) == ["iPhone A", "iPhone-B"])
    #expect(files.last?.isPrevious == true)
    #expect(try folder.read(files.first { $0.device == "iPhone-B" }!) == Data("other".utf8))

    folder.remove(device: "iPhone A")
    #expect(folder.backups().map(\.device) == ["iPhone-B"])
}

@Test func aFailedWriteLeavesTheFilesThatWereThere() throws {
    let folder = BackupFolder(directory: temporaryDirectory("backup"), coordinated: false)
    try folder.write(Data("good".utf8), device: "iPhone")
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.directory.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.directory.path) }

    #expect(throws: (any Error).self) { try folder.write(Data("new".utf8), device: "iPhone") }
    let latest = folder.directory.appending(path: "Wingspot-backup-iPhone.wingspotbackup")
    #expect(try Data(contentsOf: latest) == Data("good".utf8))
}

@Test func aFileICloudHasNotDownloadedIsListed() throws {
    let directory = temporaryDirectory("backup")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data().write(to: directory.appending(path: ".Wingspot-backup-iPad.wingspotbackup.icloud"))
    try Data().write(to: directory.appending(path: "notes.txt"))
    let files = BackupFolder(directory: directory, coordinated: false).backups()
    #expect(files.map(\.device) == ["iPad"])
    #expect(files.first?.url.lastPathComponent == "Wingspot-backup-iPad.wingspotbackup")
}

@MainActor @Test func aBurstOfChangesWritesOnceAndAnUnchangedLogbookNothing() async throws {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let context = try makeContext()
    let tracks = FlightTrackFiles(directory: temporaryDirectory("tracks"))
    let directory = temporaryDirectory("backup")
    let writes = Counter()
    let backup = AutoBackup(
        defaults: defaults, delay: .milliseconds(100),
        folder: { writes.value += 1; return BackupFolder(directory: directory, coordinated: false) },
        snapshot: { try BackupService(context: context, tracks: tracks).snapshot(app: "test") }
    )

    // Off: nothing happens.
    context.insert(pendingCheckIn())
    try context.save()
    backup.schedule()
    try await Task.sleep(for: .milliseconds(250))
    #expect(writes.value == 0)

    defaults.set(true, forKey: AutoBackup.isOnKey)
    for _ in 0..<5 { backup.schedule() }
    // Tests run side by side, so the delay can take longer than asked; wait for the write, then a while longer for a second one.
    for _ in 0..<100 where backup.lastBackup == nil { try await Task.sleep(for: .milliseconds(50)) }
    try await Task.sleep(for: .milliseconds(300))
    #expect(writes.value == 1)
    #expect(backup.lastBackup != nil && backup.problem == nil)
    let file = try #require(BackupFolder(directory: directory, coordinated: false).backups().first)
    #expect(try BackupCodec.decode(Data(contentsOf: file.url)).checkins.count == 1)

    await backup.backupNow()
    #expect(writes.value == 1)

    try tracks.save(route, for: UUID())
    await backup.backupNow()
    #expect(writes.value == 2)
    #expect(BackupFolder(directory: directory, coordinated: false).backups().count == 2)
}

@MainActor @Test func renamingTheDeviceMovesItsFilesAndAMissingFolderIsTold() async throws {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    defaults.set(true, forKey: AutoBackup.isOnKey)
    let context = try makeContext()
    context.insert(pendingCheckIn())
    try context.save()
    let directory = temporaryDirectory("backup")
    let reachable = Counter()
    reachable.value = 1
    let backup = AutoBackup(
        defaults: defaults, delay: .seconds(60),
        folder: { reachable.value == 1 ? BackupFolder(directory: directory, coordinated: false) : nil },
        snapshot: { try BackupService(context: context, tracks: FlightTrackFiles(directory: directory.appending(path: "none"))).snapshot(app: "test") }
    )
    #expect(backup.device.hasPrefix("iPhone "))

    await backup.backupNow()
    backup.device = "Kitchen phone"
    await backup.backupNow()
    #expect(BackupFolder(directory: directory, coordinated: false).backups().map(\.device) == ["Kitchen phone"])

    reachable.value = 0
    backup.device = "Work phone"
    await backup.backupNow()
    #expect(backup.problem == .unavailable)
}
