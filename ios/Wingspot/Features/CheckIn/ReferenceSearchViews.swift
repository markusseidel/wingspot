import ReferenceData
import SwiftUI

/// A searchable list that picks one item from the reference database.
private struct ReferenceSearchView<Item: Identifiable & Hashable & Sendable, Row: View>: View {
    let title: String
    let prompt: String
    let clearTitle: String
    @Binding var selection: Item?
    let search: @Sendable (ReferenceDatabase, String) async throws -> [Item]
    @ViewBuilder let row: (Item) -> Row

    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Item] = []
    @State private var isSearchPresented = true

    var body: some View {
        List {
            if selection != nil, query.isEmpty {
                Button(clearTitle, role: .destructive) { choose(nil) }
            }
            ForEach(results) { item in
                Button { choose(item) } label: { row(item) }
                    .foregroundStyle(.primary)
            }
        }
        .overlay { placeholder }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, isPresented: $isSearchPresented,
                    placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
        .autocorrectionDisabled()
        .task(id: query) { await runSearch() }
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

    var body: some View {
        ReferenceSearchView(
            title: "Aircraft type", prompt: "A388, Boeing 737, CRJ900", clearTitle: "Remove type",
            selection: $selection, search: { try await $0.searchTypes($1) }
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

    var body: some View {
        ReferenceSearchView(
            title: "Airport", prompt: "FRA, Frankfurt, Wien", clearTitle: "No airport",
            selection: $selection, search: { try await $0.searchAirports($1) }
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
    }
}
