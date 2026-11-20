import Account
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
    @State private var friends: [PersonTag] = []
    @State private var isLoading = true
    @State private var search = ""

    private var shown: [PersonTag] {
        // People already chosen stay in the list, even if they can no longer be tagged, so they can be taken off.
        let all = friends + selection.filter { chosen in !friends.contains { $0.id == chosen.id } }
        let text = search.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(text) || $0.username.localizedCaseInsensitiveContains(text) }
    }

    var body: some View {
        List {
            if friends.isEmpty, selection.isEmpty {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Friends you follow and who follow you back show up here.").foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(shown) { friend in
                        let isChosen = selection.contains { $0.id == friend.id }
                        Button {
                            toggle(friend)
                        } label: {
                            HStack {
                                Text(verbatim: friend.name).foregroundStyle(.primary)
                                Spacer()
                                if isChosen { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                        .disabled(!isChosen && selection.count >= maxTaggedFriends)
                        .accessibilityAddTraits(isChosen ? .isSelected : [])
                    }
                } footer: {
                    Text("The friends you choose will see this check-in. Up to \(maxTaggedFriends).")
                }
            }
        }
        .navigationTitle("With")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: Text("Search friends"))
        .task {
            friends = await feed.taggableFriends()
            isLoading = false
        }
    }

    private func toggle(_ friend: PersonTag) {
        if let index = selection.firstIndex(where: { $0.id == friend.id }) {
            selection.remove(at: index)
        } else if selection.count < maxTaggedFriends {
            selection.append(friend)
        }
    }
}
