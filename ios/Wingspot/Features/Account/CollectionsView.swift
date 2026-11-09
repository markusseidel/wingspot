import Account
import Persistence
import SwiftData
import SwiftUI

/// What has been seen: aircraft, types and airports, from the check-ins on this iPhone.
struct CollectionsView: View {
    @Environment(AccountStore.self) private var account
    @Query private var all: [LocalCheckIn]
    @State private var tab = Tab.aircraft

    private enum Tab: CaseIterable {
        case aircraft, types, airports

        var title: LocalizedStringKey {
            switch self {
            case .aircraft: "Aircraft"
            case .types: "Types"
            case .airports: "Airports"
            }
        }
    }

    var body: some View {
        let lists = CheckInCollections(all, userID: account.userID)
        let airportIDs = self.airportIDs
        let entries = switch tab {
        case .aircraft: lists.aircraft
        case .types: lists.types
        case .airports: lists.airports
        }
        List {
            Section {
                Picker("Collections", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            if entries.isEmpty {
                Text("Nothing here yet")
                    .foregroundStyle(.secondary)
            } else {
                Section {
                    ForEach(entries) { entry in
                        row(entry, airportID: tab == .airports ? airportIDs[entry.title] : nil)
                    }
                }
            }
        }
        .navigationTitle("Collections")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            NavigationLink {
                AirportsMapView()
            } label: {
                Image(systemName: "map")
            }
            .accessibilityLabel("Airports map")
        }
    }

    /// The airport rows open the airport's page, which needs the ID that the list itself doesn't carry.
    private var airportIDs: [String: Int] {
        var found: [String: Int] = [:]
        for checkIn in all {
            if let code = checkIn.airportCode, let id = checkIn.airportID { found[code] = id }
        }
        return found
    }

    @ViewBuilder
    private func row(_ entry: CheckInCollections.Entry, airportID: Int?) -> some View {
        if let airportID {
            NavigationLink { AirportPageView(airportID: airportID) } label: { rowContent(entry) }
        } else if tab == .types {
            NavigationLink { TypePageView(typeCode: entry.id) } label: { rowContent(entry) }
        } else {
            rowContent(entry)
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
}
