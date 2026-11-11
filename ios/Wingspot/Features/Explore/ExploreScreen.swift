import Account
import Persistence
import ReferenceData
import SwiftData
import SwiftUI
import WingspotCore

/// The Explore tab: one search for people, airports and aircraft types, and the airports near you.
struct ExploreScreen: View {
    @Environment(AccountStore.self) private var account
    @Environment(SocialStore.self) private var social
    @Environment(TermsStore.self) private var terms
    @Environment(ReferenceDataStore.self) private var referenceData
    @Query private var all: [LocalCheckIn]
    @State private var query = ""
    @State private var airports: [Airport] = []
    @State private var types: [AircraftType] = []
    @State private var people: [Person] = []

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }
    private var isSearching: Bool { trimmed.count >= 2 }
    private var canSearchPeople: Bool { account.userID != nil && terms.hasAccepted }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                List {
                    if isSearching {
                        results
                    } else {
                        NearbyAirportsSection()
                        if canSearchPeople { BusyAirportsSection() }
                    }
                }
            }
            .tabHeader("Explore") {
                NavigationLink { ExploreMapView() } label: { Image(systemName: "map") }
                    .accessibilityLabel("Map")
            }
            .task(id: SearchKey(text: trimmed, dataVersion: referenceData.database?.dataVersion, people: canSearchPeople)) {
                await search()
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search people, airports and aircraft", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear")
            }
        }
        .padding(10)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private struct SearchKey: Hashable {
        let text: String
        let dataVersion: String?
        let people: Bool
    }

    @ViewBuilder
    private var results: some View {
        if canSearchPeople, !people.isEmpty {
            Section("People") {
                ForEach(people) { person in
                    NavigationLink { PersonDetailView(person: person) } label: { PersonRow(person: person) }
                }
            }
        }
        if canSearchPeople, Self.looksLikeRegistration(trimmed) {
            Section("Aircraft") {
                NavigationLink { RegistrationPageView(registration: trimmed) } label: {
                    Label {
                        Text("Look up \(trimmed.uppercased())")
                    } icon: {
                        Image(systemName: "airplane")
                    }
                }
            }
        }
        if !airports.isEmpty {
            Section("Airports") {
                ForEach(airports) { airport in
                    NavigationLink { AirportPageView(airportID: airport.id) } label: { AirportRow(airport: airport) }
                }
            }
        }
        if !types.isEmpty {
            let mine = Dictionary(uniqueKeysWithValues: CheckInCollections(all, userID: account.userID).types.map { ($0.id, $0.count) })
            Section("Aircraft types") {
                ForEach(types) { type in
                    NavigationLink { TypePageView(typeCode: type.icaoCode) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: type.icaoCode).font(.headline)
                                Text(verbatim: type.name).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let count = mine[type.icaoCode] {
                                Text(verbatim: "\(count)×").font(.headline)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        if people.isEmpty, airports.isEmpty, types.isEmpty, !(canSearchPeople && Self.looksLikeRegistration(trimmed)) {
            Text("Nothing found").foregroundStyle(.secondary)
        }
        if !canSearchPeople {
            Section {} footer: {
                Text("Sign in and agree to the community rules in the Feed tab to find people.")
            }
        }
    }

    /// A registration has letters and a digit or a hyphen, such as D-AIPC or N123AB. Whether it exists is the server's answer.
    static func looksLikeRegistration(_ text: String) -> Bool {
        guard text.range(of: "^[A-Za-z0-9]{1,2}-?[A-Za-z0-9]{2,5}$", options: .regularExpression) != nil else { return false }
        return text.contains("-") || text.contains { $0.isNumber }
    }

    private func search() async {
        guard isSearching else {
            airports = []
            types = []
            people = []
            return
        }
        // Wait for a pause in typing. A new keystroke cancels this task.
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        if let database = referenceData.database {
            airports = (try? await database.searchAirports(trimmed, limit: 8)) ?? []
            types = (try? await database.searchTypes(trimmed, limit: 8)) ?? []
        } else {
            airports = []
            types = []
        }
        if canSearchPeople {
            people = (try? await social.search(trimmed)) ?? []
        } else {
            people = []
        }
    }
}

/// An airport in a list: the code, the name and the city.
struct AirportRow: View {
    let airport: Airport
    var distanceKm: Double?
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometres

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: airport.code).font(.headline)
                Text(verbatim: [airport.name, airport.city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if let distanceKm {
                Text(verbatim: unit.format(km: Int(distanceKm.rounded()))).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Airports close to the phone. It asks for the location only when the person taps, and remembers that they did.
struct NearbyAirportsSection: View {
    @Environment(ReferenceDataStore.self) private var referenceData
    @AppStorage("exploreUsesLocation") private var usesLocation = false
    @State private var nearby: [(airport: Airport, distanceKm: Double)] = []
    @State private var isLoading = false
    @State private var unavailable = false

    var body: some View {
        Section {
            if referenceData.database == nil {
                Text("The airport data isn't on this iPhone yet. Open the app once while online.")
                    .foregroundStyle(.secondary)
            } else if !usesLocation {
                Button("Show airports near me") { usesLocation = true }
            } else if isLoading, nearby.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else if unavailable {
                Text("Your location isn't available. You can allow it in the iPhone settings, or search for an airport.")
                    .foregroundStyle(.secondary)
            } else if nearby.isEmpty {
                Text("No airports within 150 km.").foregroundStyle(.secondary)
            } else {
                ForEach(nearby, id: \.airport.id) { item in
                    NavigationLink { AirportPageView(airportID: item.airport.id) } label: {
                        AirportRow(airport: item.airport, distanceKm: item.distanceKm)
                    }
                }
            }
        } header: {
            Text("Airports near you")
        } footer: {
            if !usesLocation {
                Text("Your location is used on this iPhone only, to sort the list.")
            }
        }
        .task(id: LoadKey(on: usesLocation, dataVersion: referenceData.database?.dataVersion)) {
            await load()
        }
    }

    private struct LoadKey: Hashable {
        let on: Bool
        let dataVersion: String?
    }

    private func load() async {
        guard usesLocation, let database = referenceData.database else { return }
        isLoading = true
        defer { isLoading = false }
        guard let position = await LocationProvider.currentPosition() else {
            unavailable = true
            return
        }
        unavailable = false
        nearby = (try? await database.airports(near: position, withinKm: 150, limit: 10)) ?? []
    }
}

/// The airports with the most check-ins in the last week among the ones you may see.
struct BusyAirportsSection: View {
    @Environment(FeedStore.self) private var feed
    @Environment(AccountStore.self) private var account
    @State private var airports: [ActiveAirport] = []
    @State private var hasLoaded = false
    @State private var failed = false

    var body: some View {
        Section {
            if !hasLoaded {
                if failed {
                    Label("Couldn't load this. Check your connection.", systemImage: "wifi.slash").foregroundStyle(.secondary)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            } else if airports.isEmpty {
                Text("Nothing yet this week.").foregroundStyle(.secondary)
            } else {
                ForEach(airports) { airport in
                    NavigationLink { AirportPageView(airportID: airport.airportID) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: airport.code).font(.headline)
                                Text(verbatim: [airport.name, airport.city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Text("\(airport.checkIns) check-ins").font(.subheadline).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        } header: {
            Text("Busy this week")
        } footer: {
            Text("Counts include only check-ins you are allowed to see.")
        }
        .task(id: account.userID) {
            do {
                airports = try await feed.activeAirports(days: 7, limit: 10)
                hasLoaded = true
                failed = false
            } catch {
                failed = true
            }
        }
    }
}
