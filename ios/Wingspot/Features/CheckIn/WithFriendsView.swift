import Account
import Persistence
import SwiftData
import SwiftUI

/// The most friends one check-in takes. The server cuts the list at the same number.
let maxTaggedFriends = 8

/// The "With" row of a form: the friends who were with you, and a list to choose them from.
struct WithFriendsRow: View {
    @Binding var selection: [PersonTag]

    var body: some View {
        NavigationLink {
            FriendPickerView(selection: $selection)
        } label: {
            LabeledContent("With", value: selection.isEmpty ? String(localized: "Optional") : selection.map(\.name).formatted())
        }
    }
}

/// Your mutual friends, to choose the ones who were with you. They get to see the check-in.
struct FriendPickerView: View {
    @Binding var selection: [PersonTag]

    @Environment(FeedStore.self) private var feed
    @Query private var local: [LocalCheckIn]
    @State private var friends: [PersonTag] = []
    @State private var isLoading = true
    @State private var search = ""
    @FocusState private var isSearching: Bool

    /// Everyone to choose from. People already chosen stay in, even if they can no longer be tagged, so they can be taken off.
    private var everyone: [PersonTag] {
        friends + selection.filter { chosen in !friends.contains { $0.id == chosen.id } }
    }

    /// The friends you flew with most often, from the check-ins on this phone.
    private var often: [PersonTag] {
        var counts: [UUID: Int] = [:]
        for checkIn in local { for id in checkIn.taggedIDs ?? [] { counts[id, default: 0] += 1 } }
        return everyone.filter { counts[$0.id, default: 0] > 0 }
            .sorted { (counts[$0.id] ?? 0, $1.name) > (counts[$1.id] ?? 0, $0.name) }
            .prefix(3).map { $0 }
    }

    private var matches: [PersonTag] {
        let text = search.trimmingCharacters(in: .whitespaces)
        return everyone.filter { $0.name.localizedCaseInsensitiveContains(text) || $0.username.localizedCaseInsensitiveContains(text) }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageSearchField(prompt: "Search friends", text: $search, isFocused: $isSearching)
            List {
                if everyone.isEmpty {
                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Friends you follow and who follow you back show up here.").foregroundStyle(.secondary)
                    }
                } else if search.trimmingCharacters(in: .whitespaces).isEmpty {
                    let frequent = often
                    if !frequent.isEmpty {
                        Section("Often flown with") { ForEach(frequent) { row($0) } }
                    }
                    Section {
                        ForEach(everyone.filter { friend in !frequent.contains { $0.id == friend.id } }) { row($0) }
                    } header: {
                        if !frequent.isEmpty { Text("All friends") }
                    } footer: {
                        Text("The friends you choose will see this check-in. Up to \(maxTaggedFriends).")
                    }
                } else {
                    ForEach(matches) { row($0) }
                }
            }
            .overlay {
                if !search.trimmingCharacters(in: .whitespaces).isEmpty, matches.isEmpty { ContentUnavailableView.search(text: search) }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("With")
        .navigationBarTitleDisplayMode(.inline)
        .autocorrectionDisabled()
        .task {
            friends = await feed.taggableFriends()
            isLoading = false
        }
    }

    private func row(_ friend: PersonTag) -> some View {
        let isChosen = selection.contains { $0.id == friend.id }
        return Button {
            toggle(friend)
        } label: {
            HStack(spacing: 12) {
                AvatarView(id: friend.id, name: friend.name, size: 36)
                Text(verbatim: friend.name).foregroundStyle(.primary)
                Spacer()
                if isChosen { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
        .disabled(!isChosen && selection.count >= maxTaggedFriends)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    private func toggle(_ friend: PersonTag) {
        if let index = selection.firstIndex(where: { $0.id == friend.id }) {
            selection.remove(at: index)
        } else if selection.count < maxTaggedFriends {
            selection.append(friend)
        }
    }
}
