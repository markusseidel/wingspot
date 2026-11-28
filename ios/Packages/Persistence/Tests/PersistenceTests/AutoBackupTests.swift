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

@MainActor @Test func theBackupHoldsTheWholeLogbookAndRestoresWhatTheServerHasAsSent() throws {
    let context = try makeContext()
    let tracks = FlightTrackFiles(directory: temporaryDirectory("tracks"))
    let owner = UUID()
    #expect(try BackupService(context: context, tracks: tracks).snapshot(app: "test").isEmpty)

    let synced = pendingCheckIn()
    synced.syncState = SyncState.synced.rawValue
    synced.ownerID = owner
    let pending = pendingCheckIn()
    context.insert(synced)
    context.insert(pending)
    try context.save()
    try tracks.save(route, for: synced.id)
    let document = try BackupService(context: context, tracks: tracks).make(app: "test")
    #expect(document.schema == 2)
    #expect(document.checkins.count == 2 && document.routes.features.count == 1)
    let sent = try #require(document.checkins.first { $0.id == synced.id.uuidString.lowercased() })
    #expect(sent.onServer == true && sent.ownerId == owner.uuidString.lowercased())
    #expect(document.checkins.first { $0.id == pending.id.uuidString.lowercased() }?.onServer == nil)

    let other = try makeContext()
    let result = try BackupService(context: other, tracks: FlightTrackFiles(directory: temporaryDirectory("tracks")))
        .restore(BackupCodec.decode(BackupCodec.encode(document)), replaceRoutes: false, userID: UUID())
    #expect(result.checkIns == 2 && result.routes == 1)
    let restored = try other.fetch(FetchDescriptor<LocalCheckIn>())
    let back = try #require(restored.first { $0.id == synced.id })
    #expect(back.syncState == SyncState.synced.rawValue && back.ownerID == owner)
    let again = try #require(restored.first { $0.id == pending.id })
    #expect(again.syncState == SyncState.pending.rawValue && again.ownerID == nil)
}

@Test func theFolderKeepsTheLatestAndThePreviousFile() throws {
    let folder = BackupFolder(directory: temporaryDirectory("backup"), coordinated: false)
    try folder.write(Data("one".utf8), device: "iPhone A")
    try folder.write(Data("two".utf8), device: "iPhone A")
    try folder.write(Data("three".utf8), device: "iPhone A")
    try folder.write(Data("other".utf8), device: "iPhone/B")

    let latest = folder.directory.appending(path: "Wingspotted-backup-iPhone A.wingspotbackup")
    let previous = folder.directory.appending(path: "Wingspotted-backup-iPhone A-previous.wingspotbackup")
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
    let latest = folder.directory.appending(path: "Wingspotted-backup-iPhone.wingspotbackup")
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

@Test func backupsFromBeforeTheRenameAreListedAndTakenOver() throws {
    let folder = BackupFolder(directory: temporaryDirectory("backup"), coordinated: false)
    try FileManager.default.createDirectory(at: folder.directory, withIntermediateDirectories: true)
    try Data("old latest".utf8).write(to: folder.directory.appending(path: "Wingspot-backup-iPhone.wingspotbackup"))
    try Data("old previous".utf8).write(to: folder.directory.appending(path: "Wingspot-backup-iPhone-previous.wingspotbackup"))
    try Data("other".utf8).write(to: folder.directory.appending(path: "Wingspot-backup-iPad.wingspotbackup"))
    #expect(folder.backups().count == 3)

    try folder.write(Data("new".utf8), device: "iPhone")
    let names = Set(try FileManager.default.contentsOfDirectory(atPath: folder.directory.path))
    #expect(names == ["Wingspotted-backup-iPhone.wingspotbackup", "Wingspotted-backup-iPhone-previous.wingspotbackup",
                      "Wingspot-backup-iPad.wingspotbackup"])
    let previous = folder.directory.appending(path: "Wingspotted-backup-iPhone-previous.wingspotbackup")
    #expect(try Data(contentsOf: previous) == Data("old latest".utf8))
    #expect(Set(folder.backups().map(\.device)) == ["iPhone", "iPad"])

    folder.remove(device: "iPad")
    #expect(folder.backups().map(\.device) == ["iPhone", "iPhone"])
}

@MainActor
private func makeBackup(_ defaults: UserDefaults, _ context: ModelContext, _ directory: URL, reachable: Counter? = nil, writes: Counter? = nil) -> AutoBackup {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return AutoBackup(
        defaults: defaults, calendar: calendar,
        folder: {
            writes?.value += 1
            return reachable?.value == 0 ? nil : BackupFolder(directory: directory, coordinated: false)
        },
        snapshot: { try BackupService(context: context, tracks: FlightTrackFiles(directory: directory.appending(path: "none"))).snapshot(app: "test") }
    )
}

private func date(_ text: String) -> Date { try! Date(text, strategy: .iso8601) }

@MainActor @Test func aBackupIsMadeWhenTheChosenPeriodHasPassed() async throws {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let context = try makeContext()
    context.insert(pendingCheckIn())
    try context.save()
    let writes = Counter()
    let backup = makeBackup(defaults, context, temporaryDirectory("backup"), writes: writes)

    // Off: never due, but "Back up now" still works.
    #expect(!backup.isDue())
    await backup.backupIfDue()
    #expect(writes.value == 0)
    await backup.backupNow(now: date("2026-11-27T21:00:00Z"))
    #expect(writes.value == 1 && backup.lastSize ?? 0 > 0 && backup.problem == nil)

    defaults.set(AutoBackup.Frequency.daily.rawValue, forKey: "autoBackupFrequency")
    // 22:00 in Berlin, the same day: not due. The next morning: due.
    #expect(!backup.isDue(now: date("2026-11-27T21:30:00Z")))
    #expect(backup.isDue(now: date("2026-11-28T06:00:00Z")))
    await backup.backupIfDue(now: date("2026-11-28T06:00:00Z"))
    #expect(writes.value == 2 && backup.lastBackup == date("2026-11-28T06:00:00Z"))

    defaults.set(AutoBackup.Frequency.weekly.rawValue, forKey: "autoBackupFrequency")
    #expect(!backup.isDue(now: date("2026-12-04T12:00:00Z")))
    #expect(backup.isDue(now: date("2026-12-05T06:00:00Z")))

    defaults.set(AutoBackup.Frequency.monthly.rawValue, forKey: "autoBackupFrequency")
    #expect(!backup.isDue(now: date("2026-12-27T12:00:00Z")))
    #expect(backup.isDue(now: date("2026-12-28T06:00:00Z")))
}

@MainActor @Test func anEmptyLogbookWritesNothingAndTurningItOnBacksUpAtOnce() async throws {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    defaults.set(true, forKey: "autoBackupOn")
    let context = try makeContext()
    let directory = temporaryDirectory("backup")
    let backup = makeBackup(defaults, context, directory)
    // The switch of the first build counts as daily.
    #expect(backup.frequency == .daily)

    await backup.backupNow()
    #expect(backup.nothingToBackUp && backup.lastBackup == nil)

    context.insert(pendingCheckIn())
    try context.save()
    backup.frequency = .off
    backup.frequency = .weekly
    for _ in 0..<100 where backup.lastBackup == nil { try await Task.sleep(for: .milliseconds(20)) }
    #expect(backup.lastBackup != nil && !backup.nothingToBackUp)
    #expect(BackupFolder(directory: directory, coordinated: false).backups().count == 1)
}

@MainActor @Test func renamingTheDeviceMovesItsFilesAndAMissingFolderIsTold() async throws {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let context = try makeContext()
    context.insert(pendingCheckIn())
    try context.save()
    let directory = temporaryDirectory("backup")
    let reachable = Counter()
    reachable.value = 1
    let backup = makeBackup(defaults, context, directory, reachable: reachable)
    #expect(backup.device.hasPrefix("iPhone "))

    await backup.backupNow()
    backup.device = "Kitchen phone"
    await backup.backupNow()
    #expect(BackupFolder(directory: directory, coordinated: false).backups().map(\.device) == ["Kitchen phone"])

    reachable.value = 0
    await backup.backupNow()
    #expect(backup.problem == .unavailable)
}
