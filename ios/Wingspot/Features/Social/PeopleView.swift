import Account
import SwiftUI

/// Finding people, and the lists of who you follow, who follows you and who you blocked.
struct PeopleView: View {
    @Environment(SocialStore.self) private var social
    @State private var query = ""
    @State private var results: [Person] = []
    @State private var isSearching = false
    @State private var failure: AccountError?

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }
    private var isSearchingText: Bool { trimmed.count >= 2 }

    var body: some View {
        List {
            if isSearchingText {
                if results.isEmpty, !isSearching {
                    Text("No one found").foregroundStyle(.secondary)
                }
                ForEach(results) { person in
                    NavigationLink { PersonDetailView(person: person) } label: { PersonRow(person: person) }
                }
            } else {
                Section {
                    NavigationLink("Following") { PeopleListView(list: .following) }
                    NavigationLink("Followers") { PeopleListView(list: .followers) }
                    NavigationLink("Blocked") { PeopleListView(list: .blocked) }
                } footer: {
                    Text("Type at least two letters of a username to find people.")
                }
            }
        }
        .navigationTitle("People")
        .searchable(text: $query, prompt: "Search by username")
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .task(id: trimmed) { await search() }
        .alert("Couldn't complete this", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            if let failure { Text(failure.message) }
        }
    }

    private func search() async {
        guard isSearchingText else {
            results = []
            return
        }
        // Wait for a pause in typing. A new keystroke cancels this task.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            results = try await social.search(trimmed)
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled { failure = (error as? AccountError) ?? .unknown }
        }
    }
}

struct PersonRow: View {
    let person: Person

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: person.displayName ?? person.username).font(.headline)
            HStack(spacing: 6) {
                Text(verbatim: "@\(person.username)")
                if person.isFriend {
                    Text("Friends")
                } else if person.followsYou {
                    Text("Follows you")
                } else if person.isFollowing {
                    Text("Following")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One of the lists behind the People screen.
struct PeopleListView: View {
    enum Kind {
        case following, followers, blocked

        var title: LocalizedStringKey {
            switch self {
            case .following: "Following"
            case .followers: "Followers"
            case .blocked: "Blocked"
            }
        }
    }

    let list: Kind

    @Environment(SocialStore.self) private var social
    @State private var people: [Person] = []
    @State private var isLoading = true
    @State private var failure: AccountError?

    var body: some View {
        List {
            if isLoading {
                ProgressView()
            } else if let failure {
                Text(failure.message).foregroundStyle(.secondary)
            } else if people.isEmpty {
                Text("Nobody here yet").foregroundStyle(.secondary)
            } else if list == .blocked {
                ForEach(people) { person in
                    HStack {
                        PersonRow(person: person)
                        Spacer()
                        Button("Unblock") { unblock(person) }
                            .buttonStyle(.bordered)
                    }
                }
            } else {
                ForEach(people) { person in
                    NavigationLink { PersonDetailView(person: person) } label: { PersonRow(person: person) }
                }
            }
        }
        .navigationTitle(list.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            switch list {
            case .following: people = try await social.following()
            case .followers: people = try await social.followers()
            case .blocked: people = try await social.blocked()
            }
            failure = nil
        } catch {
            failure = (error as? AccountError) ?? .unknown
        }
        isLoading = false
    }

    private func unblock(_ person: Person) {
        Task {
            do {
                try await social.unblock(person.id)
                people.removeAll { $0.id == person.id }
            } catch {
                failure = (error as? AccountError) ?? .unknown
            }
        }
    }
}
