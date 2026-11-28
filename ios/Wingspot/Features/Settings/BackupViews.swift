import Account
import Persistence
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Wingspot's own backup file (docs/BACKUP-FORMAT.md), declared in Info.plist.
    static let wingspotBackup = UTType(exportedAs: "site.wingspot.backup", conformingTo: .data)
}

/// A backup file picked in Settings or on the first screen, or opened into Wingspot from Files or Mail, waiting for the restore review
/// (#310). Like `KmlInbox`, it waits because a file can arrive before any screen is on show.
@MainActor @Observable
final class BackupInbox {
    static let shared = BackupInbox()
    var pending: URL?

    static func isBackup(_ url: URL) -> Bool { url.pathExtension.lowercased() == "wingspotbackup" }
}

/// Settings > Backup: make a backup file and share it, or pick one to restore.
struct BackupSection: View {
    @Environment(\.modelContext) private var modelContext
    @State private var file: SharedFile?
    @State private var isPicking = false
    @State private var failed = false

    var body: some View {
        Section {
            Button("Create backup", systemImage: "square.and.arrow.up") { create() }
            Button("Restore from backup", systemImage: "square.and.arrow.down") { isPicking = true }
        } header: {
            Text("Backup")
        } footer: {
            Text("The backup holds all your check-ins and the routes of your imported flights. Photos are not in it. It contains your travel history: keep it somewhere private.")
        }
        ICloudBackupSection()
            .sheet(item: $file, onDismiss: removeFile) { ShareSheet(file: $0.url) }
        .backupPicker(isPresented: $isPicking)
        .alert("Couldn't create the backup", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        }
    }

    private func create() {
        do {
            let document = try BackupService(context: modelContext).make(app: "Wingspotted \(Bundle.main.versionLine)")
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let day = Date.now.formatted(.iso8601.year().month().day())
            let url = folder.appending(path: "Wingspotted-backup-\(day).wingspotbackup")
            try BackupCodec.encode(document).write(to: url, options: [.atomic, .completeFileProtection])
            file = SharedFile(url: url)
        } catch {
            failed = true
        }
    }

    private func removeFile() {
        guard let url = file?.url else { return }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}

extension View {
    /// Picking a backup: the ones in iCloud Drive first, then the file picker; the picked file goes to the restore review.
    func backupPicker(isPresented: Binding<Bool>) -> some View {
        modifier(BackupChooser(isPresented: isPresented))
    }

    /// Shows the restore review when a backup file waits. Only one screen in the stack does it at a time.
    func backupRestore(isEnabled: Bool) -> some View {
        modifier(BackupRestoreHost(isEnabled: isEnabled))
    }
}

private struct BackupRestoreHost: ViewModifier {
    let isEnabled: Bool
    @State private var inbox = BackupInbox.shared

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(
            get: { isEnabled && inbox.pending != nil },
            set: { if !$0 { inbox.pending = nil } }
        )) {
            if let url = inbox.pending { BackupRestoreView(url: url) }
        }
    }
}

/// Reads the file, says what it holds, and restores it when asked. Restore only adds (docs/BACKUP-PLAN.md).
struct BackupRestoreView: View {
    let url: URL

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountStore.self) private var account
    @Environment(CheckInSyncCoordinator.self) private var sync
    @State private var document: BackupDocument?
    @State private var preview: BackupPreview?
    @State private var problem: BackupError?
    @State private var replaceRoutes = false
    @State private var result: BackupResult?

    var body: some View {
        NavigationStack {
            Form {
                if let result {
                    Section {
                        Label(resultLine(result), systemImage: "checkmark.circle.fill")
                    } footer: {
                        Text("Keep the backup file somewhere safe: the routes are only on your phones and in this file.")
                    }
                } else if let problem {
                    Label(problemLine(problem), systemImage: "exclamationmark.triangle.fill")
                } else if let preview {
                    Section {
                        Text(summary(preview))
                        Toggle("Replace routes I already have", isOn: $replaceRoutes)
                    } footer: {
                        if preview.checkIns > 0, account.userID != nil {
                            Text("The check-ins are added to the account you are signed in with.")
                        }
                    }
                    if preview.routes > 0, preview.routesWithFlightHere == 0 {
                        Section {
                            Text("None of these flights are on this phone yet. Their routes show up once the flights are here, for example after you sign in with the account they belong to.")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Restore backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if result != nil || problem != nil {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                } else {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Restore") { restore() }.disabled(document == nil)
                    }
                }
            }
        }
        .task { read() }
    }

    private func read() {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let document = try BackupCodec.decode(data)
            self.document = document
            preview = try BackupService(context: modelContext).preview(document)
        } catch let error as BackupError {
            problem = error
        } catch {
            problem = .damaged
        }
    }

    private func restore() {
        guard let document else { return }
        do {
            result = try BackupService(context: modelContext).restore(document, replaceRoutes: replaceRoutes, userID: account.userID)
            sync.requestSync()
        } catch {
            problem = .damaged
        }
    }

    private func summary(_ preview: BackupPreview) -> String {
        let date = preview.created?.formatted(date: .abbreviated, time: .omitted) ?? "?"
        let source = preview.platform == "android" ? String(localized: "an Android phone") : String(localized: "an iPhone")
        return String(localized: "Backup of \(date) from \(source): \(preview.routes) routes, \(preview.checkIns) check-ins.")
    }

    private func resultLine(_ result: BackupResult) -> String {
        var line = String(localized: "Restored \(result.routes) routes and \(result.checkIns) check-ins.")
        if result.skipped > 0 { line += " " + String(localized: "Skipped \(result.skipped) that were already here.") }
        return line
    }

    private func problemLine(_ problem: BackupError) -> String {
        switch problem {
        case .notBackup: String(localized: "This is not a Wingspotted backup.")
        case .newerVersion: String(localized: "This backup was made by a newer version of Wingspotted. Please update the app.")
        case .damaged: String(localized: "The file is damaged.")
        }
    }
}
