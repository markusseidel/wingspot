import Account
import SwiftUI

extension Bundle {
    /// The version of this build as the person sees it, "0.2.0 (2026112308)".
    var versionLine: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }

    /// The build number, which the notes are compared with. 0 when it is not a number.
    var buildNumber: Int64 { Int64(object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0 }
}

/// The version of the app, and the way to "What's new". A tester needs the version when writing a bug report.
struct AboutSection: View {
    var body: some View {
        Section("About") {
            LabeledContent("Version") { Text(verbatim: Bundle.main.versionLine).textSelection(.enabled) }
            NavigationLink("What's new") { ReleaseNotesView() }
        }
    }
}

/// What changed in each build, newest first, with the installed build marked. Builds newer than the installed one come first, under
/// their own heading: they show what the next update brings.
struct ReleaseNotesView: View {
    @Environment(ReleaseNotesStore.self) private var store
    @Environment(\.locale) private var locale
    private let installed = Bundle.main.buildNumber

    var body: some View {
        List {
            if store.loadFailed {
                Section {
                    Text("Couldn't load the latest notes. Showing what was loaded before.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            let newer = store.newer(than: installed)
            if !newer.isEmpty {
                Section("Newer than your version") { ForEach(newer) { row($0) } }
            }
            let older = store.installedAndOlder(than: installed)
            if !older.isEmpty {
                Section { ForEach(older) { row($0) } }
            }
            if store.notes.isEmpty && !store.isLoading {
                ContentUnavailableView("No release notes yet", systemImage: "text.document")
            }
        }
        .navigationTitle("What's new")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if store.isLoading && store.notes.isEmpty { ProgressView() } }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
    }

    private func row(_ note: ReleaseNote) -> some View {
        let text = note.text(language: locale.language.languageCode?.identifier ?? "en")
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(verbatim: "\(note.version) (\(note.build))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                if note.isBeta { tag("Beta") }
                if note.build == installed { tag("Installed") }
                Spacer()
                Text(note.releasedAt, format: .dateTime.day().month().year()).font(.caption).foregroundStyle(.secondary)
            }
            Text(verbatim: text.title).font(.headline)
            ForEach(Array(text.lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: "•")
                    Text(verbatim: line)
                }
                .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func tag(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.tint.opacity(0.15), in: Capsule())
    }
}
