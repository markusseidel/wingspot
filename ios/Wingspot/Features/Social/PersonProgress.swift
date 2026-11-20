import Account
import SwiftUI
import WingspotCore

/// Someone's level and earned badges, loaded when their profile opens. Only what the person's privacy allows comes back.
@MainActor
@Observable
final class PersonProgressStore {
    private let backend: any PersonProgressBackend

    init(backend: any PersonProgressBackend) {
        self.backend = backend
    }

    /// `nil` when the profile can't be seen, or the request failed.
    func progress(of id: UUID) async -> UserProgress? {
        guard let data = try? await backend.personProgress(id) else { return nil }
        return try? UserProgress.decode(data)
    }
}

/// The level of a person and a link to the badges they earned, on their profile page.
struct PersonProgressSection: View {
    let person: Person
    let progress: UserProgress

    var body: some View {
        Section {
            LevelHeader(progress: progress)
            NavigationLink {
                PersonBadgesView(person: person, progress: progress)
            } label: {
                LabeledContent("Badges", value: "\(progress.badges.count)")
            }
        }
    }
}

/// The badges a person has earned. The hidden ones are never listed, and nothing is said about them.
struct PersonBadgesView: View {
    let person: Person
    let progress: UserProgress

    var body: some View {
        List {
            Section { LevelHeader(progress: progress) }
            if progress.badges.isEmpty {
                Section { Text("No badges yet").foregroundStyle(.secondary) }
            } else {
                Section {
                    ForEach(progress.badges) { BadgeRow(badge: $0) }
                }
            }
        }
        .navigationTitle(Text(verbatim: person.displayName ?? person.username))
        .navigationBarTitleDisplayMode(.inline)
    }
}
