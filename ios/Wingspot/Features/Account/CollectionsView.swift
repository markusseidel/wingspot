import Account
import Persistence
import ReferenceData
import SwiftData
import SwiftUI
import WingspotCore

/// What has been seen: aircraft, types and airports, and the flights, from the check-ins on this iPhone.
struct CollectionsView: View {
    @Environment(AccountStore.self) private var account
    @Environment(ReferenceDataStore.self) private var referenceData
    @Query private var all: [LocalCheckIn]
    @State private var tab = Tab.aircraft
    @State private var places: [Int: GeoCoordinate] = [:]
    @AppStorage(CollectionSort.dateKey) private var dateKind = CollectionSort.defaultDate
    @AppStorage(CollectionSort.ascendingKey) private var ascending = false

    private enum Tab: CaseIterable {
        case aircraft, types, airports, flights

        var title: LocalizedStringKey {
            switch self {
            case .aircraft: "Aircraft"
            case .types: "Types"
            case .airports: "Airports"
            case .flights: "Flights"
            }
        }
    }

    var body: some View {
        let lists = CheckInCollections(all, userID: account.userID)
        let flights = CheckInCollections.ordered(
            CheckInCollections.flights(in: all, userID: account.userID),
            by: CollectionSort.kind(dateKind), ascending: ascending
        )
        let entries = switch tab {
        case .aircraft: lists.aircraft
        case .types: lists.types
        case .airports: lists.airports
        case .flights: [CheckInCollections.Entry]()
        }
        List {
            Section {
                tabs
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            if tab == .flights {
                if flights.isEmpty {
                    Text("Nothing here yet").foregroundStyle(.secondary)
                } else {
                    Section {
                        ForEach(flights) { flight in
                            CheckInLink(checkIn: flight) { FlightRow(flight: flight, places: places) }
                        }
                    }
                }
            } else if entries.isEmpty {
                Text("Nothing here yet")
                    .foregroundStyle(.secondary)
            } else {
                Section {
                    ForEach(entries) { entry in
                        NavigationLink {
                            CollectionDetailView(kind: kind(of: tab), entry: entry)
                        } label: { rowContent(entry) }
                    }
                }
            }
        }
        .navigationTitle("Collections")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if tab == .flights { ToolbarItem { CollectionSortMenu(dateKind: $dateKind, ascending: $ascending) } }
            ToolbarItem {
                NavigationLink {
                    AirportsMapView()
                } label: {
                    Image(systemName: "map")
                }
                .accessibilityLabel("Airports map")
            }
        }
        .task(id: PlacesKey(ids: flightAirportIDs, dataVersion: referenceData.database?.dataVersion)) { await loadPlaces() }
    }

    /// The tabs scroll sideways, so they stay usable on small screens and with large text.
    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Tab.allCases, id: \.self) { item in
                    Button { tab = item } label: {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(tab == item ? Color.accentColor : Color(.secondarySystemFill), in: Capsule())
                            .foregroundStyle(tab == item ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(tab == item ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func kind(of tab: Tab) -> CheckInCollections.Kind {
        switch tab {
        case .aircraft: .aircraft
        case .types: .type
        default: .airport
        }
    }

    private func rowContent(_ entry: CheckInCollections.Entry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.title).font(.headline)
                if let subtitle = entry.subtitle {
                    Text(verbatim: subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: "\(entry.count)×").font(.headline)
                Text(entry.lastSeen, format: .dateTime.day().month().year())
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private struct PlacesKey: Hashable {
        let ids: Set<Int>
        let dataVersion: String?
    }

    private var flightAirportIDs: Set<Int> {
        Set(CheckInCollections.flights(in: all, userID: account.userID).flatMap { [$0.originID, $0.destinationID].compactMap { $0 } })
    }

    /// The distances of the flights come from the airports in the reference data on this iPhone, so they work offline.
    private func loadPlaces() async {
        guard let database = referenceData.database else { return }
        var found: [Int: GeoCoordinate] = [:]
        for id in flightAirportIDs {
            if let airport = try? await database.airport(id: id) { found[id] = airport.coordinate }
        }
        places = found
    }
}

/// How the lists of check-ins are sorted: by which date, and in which direction. Remembered between visits.
enum CollectionSort {
    static let dateKey = "collections.dateKind"
    static let ascendingKey = "collections.ascending"
    static let defaultDate = CheckInCollections.DateKind.flight.rawValue

    static func kind(_ raw: String) -> CheckInCollections.DateKind {
        CheckInCollections.DateKind(rawValue: raw) ?? .flight
    }
}

/// The sort menu: the date to sort by, and newest or oldest first.
struct CollectionSortMenu: View {
    @Binding var dateKind: String
    @Binding var ascending: Bool

    var body: some View {
        Menu {
            Picker("Sort by", selection: $dateKind) {
                Text("Date of the flight or sighting").tag(CheckInCollections.DateKind.flight.rawValue)
                Text("Check-in date").tag(CheckInCollections.DateKind.checkIn.rawValue)
            }
            Picker("Order", selection: $ascending) {
                Text("Newest first").tag(false)
                Text("Oldest first").tag(true)
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort")
    }
}

/// A row that opens the check-in when the server has it. One that is only on this iPhone (waiting or not accepted) shows its
/// state instead and does not open, because there is no page for it yet.
struct CheckInLink<Label: View>: View {
    let checkIn: LocalCheckIn
    @ViewBuilder let label: () -> Label

    var body: some View {
        if checkIn.syncState == SyncState.synced.rawValue {
            NavigationLink { CheckInLoaderView(id: checkIn.id) } label: { label() }
        } else {
            label()
        }
    }
}

/// Opens one of your check-ins by id: it is fetched from the server, like from a notification.
struct CheckInLoaderView: View {
    let id: UUID

    @Environment(FeedStore.self) private var feed
    @State private var item: FeedItem?
    @State private var failed = false

    var body: some View {
        Group {
            if let item {
                CheckInDetailView(item: item)
            } else if failed {
                ContentUnavailableView("Couldn't load this check-in", systemImage: "wifi.slash")
            } else {
                ProgressView()
            }
        }
        .task {
            item = await feed.checkIn(id)
            failed = item == nil
        }
    }
}

/// A flight in the flights tab: the route, the flight number and aircraft, the date and the distance.
private struct FlightRow: View {
    let flight: LocalCheckIn
    let places: [Int: GeoCoordinate]

    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometres

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "\(flight.originCode ?? "?") → \(flight.destinationCode ?? "?")")
                    .font(.system(.headline, design: .monospaced))
                if let detail {
                    Text(verbatim: detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(flight.occurredAt, format: .dateTime.day().month().year())
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let km = distanceKm { Text(verbatim: unit.format(km: km)).font(.subheadline) }
                SyncBadge(state: flight.syncState)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String? {
        let parts = [flight.flightNumber, flight.registration ?? flight.typeName ?? flight.typeICAO].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var distanceKm: Int? {
        guard let origin = flight.originID.flatMap({ places[$0] }), let destination = flight.destinationID.flatMap({ places[$0] }) else { return nil }
        return Int(GreatCircle.distanceKm(from: origin, to: destination).rounded())
    }
}

/// The sync state of a check-in that is only on this iPhone, as a small icon.
private struct SyncBadge: View {
    let state: String

    var body: some View {
        switch SyncState(rawValue: state) {
        case .rejected:
            Image(systemName: "exclamationmark.icloud").foregroundStyle(.red).accessibilityLabel("Not accepted")
        case .synced:
            EmptyView()
        default:
            Image(systemName: "icloud.and.arrow.up").foregroundStyle(.secondary).accessibilityLabel("Waiting to upload")
        }
    }
}

/// The check-ins behind one entry of the collections: an aircraft, a type or an airport. The number of check-ins here is
/// the count in the list, because both come from the same rule.
struct CollectionDetailView: View {
    let kind: CheckInCollections.Kind
    let entry: CheckInCollections.Entry

    @Environment(AccountStore.self) private var account
    @Environment(ReferenceDataStore.self) private var referenceData
    @Query private var all: [LocalCheckIn]
    @State private var airportName: String?
    @AppStorage(CollectionSort.dateKey) private var dateKind = CollectionSort.defaultDate
    @AppStorage(CollectionSort.ascendingKey) private var ascending = false

    var body: some View {
        let checkIns = CheckInCollections.checkIns(of: kind, key: entry.id, in: all, userID: account.userID)
        let shown = CheckInCollections.ordered(checkIns, by: CollectionSort.kind(dateKind), ascending: ascending)
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: entry.title).font(.title2.bold())
                    if let subtitle = airportName ?? entry.subtitle {
                        Text(verbatim: subtitle).foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Check-ins") { Text(checkIns.count, format: .number) }
                if let first = checkIns.map(\.occurredAt).min(), let last = checkIns.map(\.occurredAt).max() {
                    LabeledContent("First date") { Text(first, format: .dateTime.day().month().year()) }
                    LabeledContent("Last date") { Text(last, format: .dateTime.day().month().year()) }
                }
                publicPage(checkIns)
            }
            Section {
                ForEach(shown) { checkIn in
                    CheckInLink(checkIn: checkIn) { CheckInRow(checkIn: checkIn) }
                }
            }
        }
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem { CollectionSortMenu(dateKind: $dateKind, ascending: $ascending) } }
        .task(id: referenceData.database?.dataVersion) { await loadAirportName() }
    }

    /// The page everybody sees for this aircraft, type or airport.
    @ViewBuilder private func publicPage(_ checkIns: [LocalCheckIn]) -> some View {
        switch kind {
        case .aircraft:
            NavigationLink { RegistrationPageView(registration: entry.id) } label: { Text("Everyone's check-ins of this aircraft") }
        case .type:
            NavigationLink { TypePageView(typeCode: entry.id) } label: { Text("Everyone's check-ins of this type") }
        case .airport:
            if let id = checkIns.compactMap(\.airportID).first {
                NavigationLink { AirportPageView(airportID: id) } label: { Text("Everyone's check-ins at this airport") }
            }
        }
    }

    private func loadAirportName() async {
        guard kind == .airport, let database = referenceData.database,
              let id = all.first(where: { $0.airportCode == entry.id })?.airportID else { return }
        airportName = (try? await database.airport(id: id))?.name
    }
}
