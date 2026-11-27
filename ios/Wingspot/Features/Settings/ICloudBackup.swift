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
            snapshot: { try BackupService(context: context).snapshot(app: "Wingspot \(Bundle.main.versionLine)") }
        )
    }

    /// Backs up while the app goes to the background, asking iOS for the time it takes.
    func backupInBackground() {
        guard isOn else { return }
        var id = UIBackgroundTaskIdentifier.invalid
        id = UIApplication.shared.beginBackgroundTask(withName: "backup") {
            UIApplication.shared.endBackgroundTask(id)
            id = .invalid
        }
        Task {
            await backupNow()
            if id != .invalid { UIApplication.shared.endBackgroundTask(id) }
        }
    }
}

/// The switch for the automatic backup, with when it last worked or why it can't.
struct ICloudBackupSection: View {
    @Environment(AutoBackup.self) private var backup

    var body: some View {
        @Bindable var backup = backup
        Section {
            Toggle("Back up to iCloud Drive automatically", isOn: $backup.isOn)
            if backup.isOn {
                status
                LabeledContent("Name of this iPhone") {
                    TextField("Name of this iPhone", text: $backup.device)
                        .multilineTextAlignment(.trailing)
                        .submitLabel(.done)
                }
            }
        } footer: {
            Text("Wingspot keeps the latest backup and the one before it in the Wingspot folder of your iCloud Drive, after each change. Apple stores it; Wingspot can't read it. Each iPhone writes its own file, named after it.")
        }
    }

    @ViewBuilder private var status: some View {
        if backup.isWorking {
            Label("Backing up…", systemImage: "icloud.and.arrow.up")
        } else if let problem = backup.problem {
            Label(problemLine(problem), systemImage: "exclamationmark.icloud").foregroundStyle(.red)
        } else if let last = backup.lastBackup {
            Label("Last backup: \(last.formatted(.relative(presentation: .named)))", systemImage: "checkmark.icloud")
        } else {
            Label("No backup yet: it is made once there are routes or check-ins only on this iPhone.", systemImage: "icloud")
                .foregroundStyle(.secondary)
        }
    }

    private func problemLine(_ problem: AutoBackup.Problem) -> LocalizedStringKey {
        switch problem {
        case .unavailable: "iCloud Drive is off for Wingspot. Turn it on in the Settings app under your name > iCloud."
        case .full: "Your iCloud storage is full."
        case .failed: "The last backup failed. Wingspot tries again after the next change."
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
