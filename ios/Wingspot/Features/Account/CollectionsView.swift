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
            }
        }
        .navigationTitle("Collections")
        .navigationBarTitleDisplayMode(.inline)
    }
}
