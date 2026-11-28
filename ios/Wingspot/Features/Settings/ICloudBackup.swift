import Persistence
import SwiftData
import SwiftUI
import UIKit

extension AutoBackup {
    nonisolated static let containerID = "iCloud.site.wingspot.ios"

    /// The automatic backup into the Wingspot folder of the person's iCloud Drive (docs/ICLOUD-BACKUP-PLAN.md).
    static func iCloud(context: ModelContext) -> AutoBackup {
        AutoBackup(
            defaultDevice: UIDevice.current.model,
            folder: {
                // Nil while nobody is signed in to iCloud or iCloud Drive is off for Wingspot. Never called on the main thread.
                guard FileManager.default.ubiquityIdentityToken != nil,
                      let base = FileManager.default.url(forUbiquityContainerIdentifier: containerID) else { return nil }
                return BackupFolder(directory: base.appending(path: "Documents", directoryHint: .isDirectory))
            },
            snapshot: { try BackupService(context: context).snapshot(app: "Wingspotted \(Bundle.main.versionLine)") }
        )
    }

    /// Backs up while the app goes to the background, asking iOS for the time it takes.
    func backupInBackground() {
        guard isDue() else { return }
        var id = UIBackgroundTaskIdentifier.invalid
        id = UIApplication.shared.beginBackgroundTask(withName: "backup") {
            UIApplication.shared.endBackgroundTask(id)
            id = .invalid
        }
        Task {
            await backupIfDue()
            if id != .invalid { UIApplication.shared.endBackgroundTask(id) }
        }
    }
}

/// The automatic backup to iCloud Drive: how often, a button for now, when it last worked or why it can't.
struct ICloudBackupSection: View {
    @Environment(AutoBackup.self) private var backup

    var body: some View {
        @Bindable var backup = backup
        Section {
            Picker("Back up to iCloud Drive", selection: $backup.frequency) {
                Text("Off").tag(AutoBackup.Frequency.off)
                Text("Daily").tag(AutoBackup.Frequency.daily)
                Text("Weekly").tag(AutoBackup.Frequency.weekly)
                Text("Monthly").tag(AutoBackup.Frequency.monthly)
            }
            Button("Back up now", systemImage: "icloud.and.arrow.up") { Task { await backup.backupNow() } }
                .disabled(backup.isWorking)
            status
            HStack {
                Text("Name of this iPhone").layoutPriority(1)
                TextField("Name of this iPhone", text: $backup.device)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .submitLabel(.done)
            }
        } header: {
            Text("iCloud Drive")
        } footer: {
            Text("A full backup of your check-ins and routes, in the Wingspotted folder of your iCloud Drive. Wingspotted keeps the latest backup and the one before it. Apple stores it; Wingspotted can't read it. Each iPhone writes its own file, named after it.")
        }
        // A backup that is due is made when the page opens, so the line below shows the real state.
        .task { await backup.backupIfDue() }
    }

    @ViewBuilder private var status: some View {
        if backup.isWorking {
            Label("Backing up…", systemImage: "arrow.triangle.2.circlepath.icloud")
        } else if let problem = backup.problem {
            Label(problemLine(problem), systemImage: "exclamationmark.icloud").foregroundStyle(.red)
        } else if backup.nothingToBackUp {
            Label("Nothing to back up yet: your logbook is empty.", systemImage: "icloud").foregroundStyle(.secondary)
        } else if let last = backup.lastBackup {
            VStack(alignment: .leading, spacing: 2) {
                Label("Last backup: \(last.formatted(date: .abbreviated, time: .shortened))", systemImage: "checkmark.icloud")
                if let size = backup.lastSize {
                    Text("Size: \(size.formatted(.byteCount(style: .file)))").font(.footnote).foregroundStyle(.secondary)
                }
                if backup.frequency != .off, let next = backup.nextBackup {
                    Text("Next backup: \(next.formatted(date: .abbreviated, time: .omitted))").font(.footnote).foregroundStyle(.secondary)
                }
            }
        } else {
            Label("No backup yet.", systemImage: "icloud").foregroundStyle(.secondary)
        }
    }

    private func problemLine(_ problem: AutoBackup.Problem) -> LocalizedStringKey {
        switch problem {
        case .unavailable: "iCloud Drive is off for Wingspotted. Turn it on in the Settings app under your name > iCloud."
        case .full: "Your iCloud storage is full."
        case .failed: "The last backup failed. Wingspotted tries again next time."
        }
    }
}

/// Picking a backup to restore: the ones in iCloud Drive first, then any file. Without any in iCloud Drive, the file picker
/// opens straight away.
struct BackupChooser: ViewModifier {
    @Binding var isPresented: Bool
    @Environment(AutoBackup.self) private var backup
    @State private var files: [BackupFile] = []
    @State private var showsList = false
    @State private var showsFiles = false
    @State private var loading: URL?
    @State private var failed = false

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) {
                guard isPresented else { return }
                isPresented = false
                Task {
                    files = await backup.availableBackups()
                    if files.isEmpty { showsFiles = true } else { showsList = true }
                }
            }
            .sheet(isPresented: $showsList) { list }
            .fileImporter(isPresented: $showsFiles, allowedContentTypes: [.wingspotBackup, .json, .gzip, .data]) { picked in
                if case .success(let url) = picked { BackupInbox.shared.pending = url }
            }
    }

    private var list: some View {
        NavigationStack {
            Form {
                Section("In iCloud Drive") {
                    ForEach(files) { file in
                        Button { open(file) } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(file.device).foregroundStyle(.primary)
                                    Text(subtitle(file)).font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if loading == file.url { ProgressView() }
                            }
                        }
                        .disabled(loading != nil)
                    }
                }
                Section {
                    Button("Choose a file…", systemImage: "folder") {
                        showsList = false
                        showsFiles = true
                    }
                }
            }
            .navigationTitle("Restore backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { showsList = false } }
            }
            .alert("Couldn't download the backup from iCloud Drive", isPresented: $failed) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private func subtitle(_ file: BackupFile) -> String {
        let date = file.modified?.formatted(date: .abbreviated, time: .shortened) ?? "?"
        return file.isPrevious ? String(localized: "Previous backup, \(date)") : String(localized: "Latest backup, \(date)")
    }

    private func open(_ file: BackupFile) {
        loading = file.url
        Task {
            defer { loading = nil }
            do {
                let data = try await backup.read(file)
                let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let url = folder.appending(path: file.url.lastPathComponent)
                try data.write(to: url, options: [.atomic, .completeFileProtection])
                showsList = false
                BackupInbox.shared.pending = url
            } catch {
                failed = true
            }
        }
    }
}
