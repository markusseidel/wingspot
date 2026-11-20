import Account
import Persistence
import ReferenceData
import SwiftUI

/// A titled group of items offered before anything is typed.
struct SuggestionSection<Item: Identifiable & Hashable & Sendable> {
    let title: LocalizedStringKey
    let items: [Item]
}

/// The search field of a picker. It is part of the page, not the navigation bar: the bar's own search field folds
/// back into the title when it is cancelled, and iOS puts it at the bottom of the screen in a sheet.
struct PageSearchField: View {
    let prompt: LocalizedStringKey
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .focused(isFocused)
                .submitLabel(.search)
            if isFocused.wrappedValue || !text.isEmpty {
                Button {
                    text = ""
                    isFocused.wrappedValue = false
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.fill.tertiary, in: Capsule())
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

/// A searchable list that picks one item from the reference database.
private struct ReferenceSearchView<Item: Identifiable & Hashable & Sendable, Row: View>: View {
    let title: LocalizedStringKey
    let prompt: LocalizedStringKey
    let clearTitle: LocalizedStringKey
    @Binding var selection: Item?
    let search: @Sendable (ReferenceDatabase, String) async throws -> [Item]
    /// Offered before anything is typed.
    var suggestions: [SuggestionSection<Item>] = []
    @ViewBuilder let row: (Item) -> Row

    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Item] = []
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            list
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .autocorrectionDisabled()
        .task(id: query) { await runSearch() }
        .task {
            // The keyboard opens by itself, as the search field used to.
            try? await Task.sleep(for: .milliseconds(150))
            isFocused = true
        }
    }

    private var searchField: some View {
        PageSearchField(prompt: prompt, text: $query, isFocused: $isFocused)
    }

    private var list: some View {
        List {
            if selection != nil, query.isEmpty {
                Button(clearTitle, role: .destructive) { choose(nil) }
            }
            if query.isEmpty {
                ForEach(suggestions.indices, id: \.self) { index in
                    let section = suggestions[index]
                    Section(section.title) {
                        ForEach(section.items) { item in
                            Button { choose(item) } label: { row(item) }
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            ForEach(results) { item in
                Button { choose(item) } label: { row(item) }
                    .foregroundStyle(.primary)
            }
        }
        .overlay { placeholder }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder private var placeholder: some View {
        if referenceData.database == nil {
            ContentUnavailableView("Not downloaded yet", systemImage: "arrow.down.circle",
                                   description: Text("Search works offline after one download while online."))
        } else if results.isEmpty, !query.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView.search(text: query)
        }
    }

    private func runSearch() async {
        guard let database = referenceData.database else { return }
        // Waits for a pause in typing. A new keystroke cancels this task.
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return }
        let found = (try? await search(database, query)) ?? []
        if !Task.isCancelled { results = found }
    }

    private func choose(_ item: Item?) {
        selection = item
        dismiss()
    }
}

struct TypeSearchView: View {
    @Binding var selection: AircraftType?
    /// The types of earlier flights with the same flight number, offered before anything is typed.
    var recent: [AircraftType] = []

    @Environment(\.modelContext) private var modelContext
    @Environment(AccountStore.self) private var account

    /// Your latest types, without the ones already offered for the flight number.
    private var latest: [AircraftType] {
        let found = (try? CheckInStore(context: modelContext).recentTypes(userID: account.userID)) ?? []
        let known = Set(recent.map(\.icaoCode))
        return found.filter { !known.contains($0.icaoCode) }
            .map { AircraftType(icaoCode: $0.icaoCode, manufacturer: $0.name, model: "") }
    }

    var body: some View {
        ReferenceSearchView(
            title: "Aircraft type", prompt: "A388, Boeing 737, CRJ900", clearTitle: "Remove type",
            selection: $selection, search: { try await $0.searchTypes($1) },
            suggestions: [
                SuggestionSection(title: "Recent on this flight number", items: recent),
                SuggestionSection(title: "Recent aircraft types", items: latest),
            ].filter { !$0.items.isEmpty }
        ) { type in
            HStack {
                Text(type.name)
                Spacer()
                Text(type.icaoCode).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
    }
}

struct AirportSearchView: View {
    @Binding var selection: Airport?

    @Environment(\.modelContext) private var modelContext
    @Environment(AccountStore.self) private var account
    @Environment(ReferenceDataStore.self) private var referenceData
    @State private var recent: [Airport] = []

    var body: some View {
        ReferenceSearchView(
            title: "Airport", prompt: "FRA, Frankfurt, Vienna", clearTitle: "No airport",
            selection: $selection, search: { try await $0.searchAirports($1) },
            suggestions: recent.isEmpty ? [] : [SuggestionSection(title: "Recent airports", items: recent)]
        ) { airport in
            HStack {
                VStack(alignment: .leading) {
                    Text(airport.name)
                    if let city = airport.city {
                        Text(city).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(airport.code).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
        .task(id: referenceData.database?.dataVersion) { await loadRecent() }
    }

    /// The airports of your latest check-ins, named from the reference data on this device.
    private func loadRecent() async {
        guard let database = referenceData.database else { return }
        let ids = (try? CheckInStore(context: modelContext).recentAirportIDs(userID: account.userID)) ?? []
        var airports = [Airport]()
        for id in ids {
            if let airport = try? await database.airport(id: id) { airports.append(airport) }
        }
        recent = airports
    }
}
