import Foundation
import Observation

/// A backup file found in the backup folder.
public struct BackupFile: Sendable, Identifiable, Equatable {
    /// Where the file is, also while iCloud has not downloaded it yet.
    public let url: URL
    /// The device label in the file name, such as "iPhone 7F3A".
    public let device: String
    public let isPrevious: Bool
    public let modified: Date?
    public var id: URL { url }
}

/// The folder the automatic backup writes into (docs/ICLOUD-BACKUP-PLAN.md): on the iPhone the app's folder in iCloud Drive, in
/// tests a temporary one. Each device keeps two files, its latest backup and the one before it, so two phones never overwrite
/// each other and a bad write never leaves nothing.
public struct BackupFolder: Sendable {
    public static let prefix = "Wingspotted-backup-"
    /// The prefix before the app was renamed to Wingspotted (docs/RENAME-WINGSPOTTED-PLAN.md). Files with it are still listed,
    /// and a device's first backup under the new name takes its old files over.
    public static let oldPrefix = "Wingspot-backup-"
    public static let fileExtension = "wingspotbackup"

    public let directory: URL
    /// Whether to coordinate with iCloud while moving files. Off in tests.
    let coordinated: Bool

    public init(directory: URL, coordinated: Bool = true) {
        self.directory = directory
        self.coordinated = coordinated
    }

    /// The label as it can stand in a file name: letters, digits, spaces and dashes, at most 40 characters.
    public static func safe(_ device: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let cleaned = String(String.UnicodeScalarView(device.unicodeScalars.map { allowed.contains($0) ? $0 : "-" }))
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "iPhone" : String(cleaned.prefix(40))
    }

    public static func fileName(device: String, previous: Bool = false, prefix: String = prefix) -> String {
        "\(prefix)\(safe(device))\(previous ? "-previous" : "").\(fileExtension)"
    }

    private func url(_ name: String) -> URL { directory.appending(path: name, directoryHint: .notDirectory) }

    /// Writes `data` as this device's latest backup. The latest one so far becomes the previous one, and the oldest goes. If
    /// anything fails, the files that were there stay.
    public func write(_ data: Data, device: String) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let latest = url(Self.fileName(device: device)), previous = url(Self.fileName(device: device, previous: true))
        adoptOldFiles(device: device)
        // Written outside the folder first, so iCloud never sees a half-written file.
        let temporary = manager.temporaryDirectory.appending(path: "\(UUID().uuidString).\(Self.fileExtension)", directoryHint: .notDirectory)
        defer { try? manager.removeItem(at: temporary) }
        try data.write(to: temporary, options: .atomic)
        try coordinate(writing: [latest, previous]) {
            if manager.fileExists(atPath: latest.path) {
                if manager.fileExists(atPath: previous.path) {
                    _ = try manager.replaceItemAt(previous, withItemAt: latest)
                } else {
                    try manager.moveItem(at: latest, to: previous)
                }
            }
            try manager.moveItem(at: temporary, to: latest)
        }
    }

    /// Renames this device's files from before the rename to Wingspotted to the new names, so the latest and the previous
    /// backup carry on. Only while the device has no file under the new name yet.
    private func adoptOldFiles(device: String) {
        let manager = FileManager.default
        for previous in [false, true] {
            let old = url(Self.fileName(device: device, previous: previous, prefix: Self.oldPrefix))
            let new = url(Self.fileName(device: device, previous: previous))
            guard manager.fileExists(atPath: old.path), !manager.fileExists(atPath: new.path) else { continue }
            try? coordinate(writing: [old, new]) { try manager.moveItem(at: old, to: new) }
        }
    }

    /// Removes both files of a device, for example after its label changed, under the old name too.
    public func remove(device: String) {
        for prefix in [Self.prefix, Self.oldPrefix] {
            let urls = [url(Self.fileName(device: device, prefix: prefix)), url(Self.fileName(device: device, previous: true, prefix: prefix))]
            try? coordinate(writing: urls) { for url in urls { try? FileManager.default.removeItem(at: url) } }
        }
    }

    /// Every backup in the folder, newest first; the files iCloud has not downloaded yet included.
    public func backups() -> [BackupFile] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        var files: [BackupFile] = []
        for raw in names {
            var name = raw
            // iCloud keeps a file it has not downloaded as ".<name>.icloud".
            if name.hasPrefix("."), name.hasSuffix(".icloud") { name = String(name.dropFirst().dropLast(7)) }
            guard let prefix = [Self.prefix, Self.oldPrefix].first(where: name.hasPrefix), name.hasSuffix(".\(Self.fileExtension)")
            else { continue }
            var label = String(name.dropFirst(prefix.count).dropLast(Self.fileExtension.count + 1))
            let isPrevious = label.hasSuffix("-previous")
            if isPrevious { label = String(label.dropLast(9)) }
            let modified = (try? url(raw).resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            files.append(BackupFile(url: url(name), device: label, isPrevious: isPrevious, modified: modified))
        }
        return files.sorted {
            if $0.isPrevious != $1.isPrevious { return !$0.isPrevious }
            return ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast)
        }
    }

    /// Reads a backup, waiting for iCloud to download it first if needed. Call it away from the main thread.
    public func read(_ file: BackupFile) throws -> Data {
        guard coordinated else { return try Data(contentsOf: file.url) }
        try? FileManager.default.startDownloadingUbiquitousItem(at: file.url)
        var result: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: file.url, options: [], error: &error) { url in
            result = Result { try Data(contentsOf: url) }
        }
        if let error { throw error }
        return try result.get()
    }

    private func coordinate(writing urls: [URL], _ body: () throws -> Void) throws {
        guard coordinated else { return try body() }
        var failure: Error?
        var error: NSError?
        NSFileCoordinator().coordinate(
            writingItemAt: urls[0], options: .forReplacing, writingItemAt: urls[1], options: .forReplacing, error: &error
        ) { _, _ in
            do { try body() } catch { failure = error }
        }
        if let error { throw error }
        if let failure { throw failure }
    }
}

/// Keeps a full backup in a folder by itself, like WhatsApp: daily, weekly or monthly, once the person chose that
/// (docs/ICLOUD-BACKUP-PLAN.md, section 8). iOS gives apps no exact timer, so the app asks `backupIfDue()` when it comes to the
/// foreground or goes to the background.
@MainActor
@Observable
public final class AutoBackup {
    public enum Frequency: String, CaseIterable, Sendable, Identifiable {
        case off, daily, weekly, monthly
        public var id: String { rawValue }
    }

    public enum Problem: Equatable, Sendable {
        /// The folder can't be reached: iCloud Drive is off for the app, or nobody is signed in to iCloud.
        case unavailable
        /// No space left.
        case full
        case failed
    }

    static let frequencyKey = "autoBackupFrequency"
    /// The switch of the first build; on counts as daily.
    static let oldIsOnKey = "autoBackupOn"
    static let deviceKey = "autoBackupDevice"
    static let writtenDeviceKey = "autoBackupWrittenDevice"
    static let lastKey = "autoBackupLast"
    static let sizeKey = "autoBackupSize"

    private let defaults: UserDefaults
    private let folder: @Sendable () async -> BackupFolder?
    private let snapshot: @MainActor () throws -> BackupSnapshot
    private let calendar: Calendar
    private var running: Task<Void, Never>?

    public private(set) var lastBackup: Date?
    /// The size of the last backup file, in bytes.
    public private(set) var lastSize: Int?
    public private(set) var problem: Problem?
    public private(set) var isWorking = false
    /// The logbook was empty at the last try, so no file was written.
    public private(set) var nothingToBackUp = false

    /// - Parameters:
    ///   - folder: where to write, or nil when it can't be reached. Called away from the main thread.
    ///   - snapshot: what to back up, read from the database.
    public init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        defaultDevice: String = "iPhone",
        folder: @escaping @Sendable () async -> BackupFolder?,
        snapshot: @escaping @MainActor () throws -> BackupSnapshot
    ) {
        self.defaults = defaults
        self.calendar = calendar
        self.folder = folder
        self.snapshot = snapshot
        lastBackup = defaults.object(forKey: Self.lastKey) as? Date
        lastSize = defaults.object(forKey: Self.sizeKey) as? Int
        if defaults.string(forKey: Self.frequencyKey) == nil, defaults.bool(forKey: Self.oldIsOnKey) {
            defaults.set(Frequency.daily.rawValue, forKey: Self.frequencyKey)
        }
        if defaults.string(forKey: Self.deviceKey) == nil {
            // A short code keeps two phones of one Apple ID apart until the person names them.
            defaults.set("\(defaultDevice) \(UUID().uuidString.prefix(4))", forKey: Self.deviceKey)
        }
    }

    public var frequency: Frequency {
        get { access(keyPath: \.frequency); return defaults.string(forKey: Self.frequencyKey).flatMap(Frequency.init) ?? .off }
        set {
            let wasOff = frequency == .off
            withMutation(keyPath: \.frequency) { defaults.set(newValue.rawValue, forKey: Self.frequencyKey) }
            if newValue == .off { problem = nil } else if wasOff { Task { await backupNow() } }
        }
    }

    /// The name this device's files carry, shown and changeable in Settings. Kept as typed, also while empty; the file name
    /// falls back to "iPhone" (`BackupFolder.safe`).
    public var device: String {
        get { access(keyPath: \.device); return defaults.string(forKey: Self.deviceKey) ?? "iPhone" }
        set { withMutation(keyPath: \.device) { defaults.set(String(newValue.prefix(40)), forKey: Self.deviceKey) } }
    }

    /// When the next backup is due, or nil when it is off or none was made yet (then it is due now).
    public var nextBackup: Date? {
        guard let lastBackup, let step = step(frequency) else { return nil }
        return calendar.date(byAdding: step, to: calendar.startOfDay(for: lastBackup))
    }

    private func step(_ frequency: Frequency) -> DateComponents? {
        switch frequency {
        case .off: nil
        case .daily: DateComponents(day: 1)
        case .weekly: DateComponents(day: 7)
        case .monthly: DateComponents(month: 1)
        }
    }

    /// Whether a backup is due: on, and the chosen period has passed, counted in calendar days, so a daily backup made at 9 in
    /// the evening is due again the next morning.
    public func isDue(now: Date = .now) -> Bool {
        guard frequency != .off else { return false }
        guard let next = nextBackup else { return true }
        return calendar.startOfDay(for: now) >= next
    }

    /// Backs up if one is due. Call it when the app comes to the foreground or goes to the background.
    public func backupIfDue(now: Date = .now) async {
        guard isDue(now: now) else { return }
        await backupNow(now: now)
    }

    /// Backs up now, also while the schedule is off ("Back up now"). Waits for a backup already running.
    public func backupNow(now: Date = .now) async {
        while let running { await running.value }
        let task = Task { await write(now: now) }
        running = task
        await task.value
        running = nil
    }

    /// The backups in the folder, newest first. Empty when the folder can't be reached.
    public func availableBackups() async -> [BackupFile] {
        guard let folder = await folder() else { return [] }
        return await Task.detached { folder.backups() }.value
    }

    /// Reads one of `availableBackups()`, downloading it first if needed.
    public func read(_ file: BackupFile) async throws -> Data {
        guard let folder = await folder() else { throw CocoaError(.fileReadNoSuchFile) }
        return try await Task.detached { try folder.read(file) }.value
    }

    private func write(now: Date) async {
        let snapshot: BackupSnapshot
        do { snapshot = try self.snapshot() } catch { problem = .failed; return }
        // An empty logbook is not worth a file, and must not replace an earlier backup.
        nothingToBackUp = snapshot.isEmpty
        if snapshot.isEmpty { return }
        isWorking = true
        defer { isWorking = false }
        guard let folder = await folder() else { problem = .unavailable; return }
        let device = self.device
        let written = defaults.string(forKey: Self.writtenDeviceKey)
        do {
            let size = try await Task.detached {
                let data = try BackupCodec.encode(snapshot.document())
                try folder.write(data, device: device)
                if let written, BackupFolder.safe(written) != BackupFolder.safe(device) { folder.remove(device: written) }
                return data.count
            }.value
            defaults.set(device, forKey: Self.writtenDeviceKey)
            defaults.set(now, forKey: Self.lastKey)
            defaults.set(size, forKey: Self.sizeKey)
            lastBackup = now
            lastSize = size
            problem = nil
        } catch let error as CocoaError where error.code == .fileWriteOutOfSpace {
            problem = .full
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(ENOSPC) {
            problem = .full
        } catch {
            problem = .failed
        }
    }
}
