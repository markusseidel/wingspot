import Account
import SwiftUI

/// Loads the comparison with one friend. `nil` when their profile can't be seen, or the request failed.
@MainActor
@Observable
final class CompareStore {
    private let backend: any CompareBackend

    init(backend: any CompareBackend) {
        self.backend = backend
    }

    func compare(with id: UUID) async throws -> CompareResult? {
        guard let data = try await backend.compare(with: id) else { return nil }
        return try CompareResult.decode(data)
    }
}

/// You next to a friend: the numbers side by side, and the airports, countries, airlines and aircraft types you share
/// or only one of you has.
struct CompareView: View {
    let person: Person

    @Environment(CompareStore.self) private var store
    @Environment(AccountStore.self) private var account
    @State private var result: CompareResult?
    @State private var failed = false
    @State private var loaded = false

    private var theirName: String { person.displayName ?? person.username }

    var body: some View {
        Group {
            if let result {
                list(result)
            } else if loaded {
                ContentUnavailableView {
                    Label(failed ? "Couldn't load the comparison" : "Nothing to compare", systemImage: failed ? "exclamationmark.triangle" : "lock")
                } description: {
                    Text(failed ? "Please check your connection and try again." : "You can only compare with people whose profile you may see.")
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: person.id) {
            do {
                result = try await store.compare(with: person.id)
                failed = false
            } catch {
                failed = true
            }
            loaded = true
        }
    }

    private func list(_ result: CompareResult) -> some View {
        List {
            Section {
                HStack {
                    side(id: account.userID, name: String(localized: "You"))
                    Spacer()
                    side(id: person.id, name: theirName)
                }
            }
            Section {
                row("Flights", result.me.flights, result.them.flights)
                row("Distance", result.me.distanceKm, result.them.distanceKm, unit: "km")
                row("Countries", result.me.countries, result.them.countries)
                row("Airports", result.me.airports, result.them.airports)
                row("Airlines", result.me.airlines, result.them.airlines)
                row("Aircraft types", result.me.types, result.them.types)
            }
            sets("Countries", result.countries, country: true)
            sets("Airports", result.airports)
            sets("Airlines", result.airlines)
            sets("Aircraft types", result.types)
            Section {
            } footer: {
                Text("Counts include only the check-ins you are allowed to see.")
            }
        }
    }

    private func side(id: UUID?, name: String) -> some View {
        VStack(spacing: 6) {
            if let id {
                AvatarView(id: id, name: name, size: 56)
            }
            Text(verbatim: name).font(.subheadline.weight(.semibold)).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    /// A number for each of you, with a bar that shows who has more.
    private func row(_ title: LocalizedStringKey, _ mine: Int, _ theirs: Int, unit: String? = nil) -> some View {
        let top = max(max(mine, theirs), 1)
        return VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            bar(value: mine, top: top, unit: unit, tint: .accentColor)
            bar(value: theirs, top: top, unit: unit, tint: .gray)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func bar(value: Int, top: Int, unit: String?, tint: Color) -> some View {
        HStack(spacing: 10) {
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 4)
                    .fill(tint)
                    .frame(width: max(proxy.size.width * CGFloat(value) / CGFloat(top), value > 0 ? 4 : 0))
            }
            .frame(height: 8)
            Text(unit.map { "\(value.formatted()) \($0)" } ?? value.formatted())
                .font(.subheadline.monospacedDigit())
                .frame(minWidth: 70, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func sets(_ title: LocalizedStringKey, _ set: CompareSet, country: Bool = false) -> some View {
        if !(set.common.isEmpty && set.mine.isEmpty && set.theirs.isEmpty) {
            Section {
                group("In common", set.common, country: country, open: country)
                group("Only you", set.mine, country: country)
                group("Only \(theirName)", set.theirs, country: country)
            } header: {
                Text(title)
            }
        }
    }

    @ViewBuilder
    private func group(_ title: LocalizedStringKey, _ items: [CompareItem], country: Bool, open: Bool = false) -> some View {
        if !items.isEmpty {
            CompareGroup(title: title, count: items.count, open: open) {
                ForEach(items) { item in
                    Text(verbatim: label(item, country: country)).font(.subheadline)
                }
            }
        }
    }

    private func label(_ item: CompareItem, country: Bool) -> String {
        if country {
            let flag = item.code.uppercased().unicodeScalars.compactMap { Unicode.Scalar(127397 + $0.value) }
                .map { String(Character($0)) }.joined()
            return "\(flag) \(Locale.current.localizedString(forRegionCode: item.code) ?? item.code)"
        }
        if let name = item.name, !name.isEmpty { return "\(item.code) · \(name)" }
        return item.code
    }
}

/// A list that opens and closes, with how many are in it.
private struct CompareGroup<Content: View>: View {
    let title: LocalizedStringKey
    let count: Int
    @State private var isExpanded: Bool
    @ViewBuilder let content: Content

    init(title: LocalizedStringKey, count: Int, open: Bool, @ViewBuilder content: () -> Content) {
        self.title = title
        self.count = count
        _isExpanded = State(initialValue: open)
        self.content = content()
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(count.formatted()).foregroundStyle(.secondary)
            }
        }
    }
}
