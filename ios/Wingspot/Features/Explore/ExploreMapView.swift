import Account
import MapKit
import Persistence
import ReferenceData
import SwiftData
import SwiftUI

/// A map with the airports that were busy this week (orange) and the ones you checked in at (blue). The positions
/// come from the downloaded airport data. Tapping a marker opens the airport's page.
struct ExploreMapView: View {
    @Environment(AccountStore.self) private var account
    @Environment(FeedStore.self) private var feed
    @Environment(TermsStore.self) private var terms
    @Environment(ReferenceDataStore.self) private var referenceData
    @Query private var all: [LocalCheckIn]
    @State private var markers: [AirportMarker] = []
    @State private var isLoading = true
    @State private var failed = false
    @State private var selected: Int?

    struct AirportMarker: Identifiable, Equatable {
        let airport: Airport
        let busy: Bool
        let mine: Bool
        var id: Int { airport.id }
    }

    private struct LoadKey: Hashable {
        let ids: Set<Int>
        let dataVersion: String?
        let user: UUID?
        let terms: Bool
    }

    var body: some View {
        let ids = CheckInStats(all, userID: account.userID).airportIDs
        Group {
            if markers.isEmpty {
                ContentUnavailableView {
                    Label("No airports to show", systemImage: "map")
                } description: {
                    if isLoading {
                        ProgressView()
                    } else if referenceData.database == nil {
                        Text("The map needs the airport data. Open the app once while online.")
                    } else {
                        Text("Busy airports and the ones you checked in at appear here.")
                    }
                }
            } else {
                Map(selection: $selected) {
                    ForEach(markers) { marker in
                        Marker(
                            marker.airport.code,
                            coordinate: CLLocationCoordinate2D(
                                latitude: marker.airport.coordinate.latitude, longitude: marker.airport.coordinate.longitude
                            )
                        )
                        .tint(marker.busy ? .orange : .blue)
                        .tag(marker.id)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 2) {
                        HStack(spacing: 16) {
                            Label("Busy this week", systemImage: "circle.fill").foregroundStyle(.orange)
                            Label("Yours", systemImage: "circle.fill").foregroundStyle(.blue)
                        }
                        if failed {
                            Text("Couldn't load the busy airports. Check your connection.").foregroundStyle(.secondary)
                        }
                    }
                    .font(.footnote)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
                }
            }
        }
        .navigationDestination(item: $selected) { AirportPageView(airportID: $0) }
        .navigationTitle("Map")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: LoadKey(ids: ids, dataVersion: referenceData.database?.dataVersion, user: account.userID, terms: terms.hasAccepted)) {
            isLoading = true
            defer { isLoading = false }
            guard let database = referenceData.database else {
                markers = []
                return
            }
            var busyIDs = Set<Int>()
            failed = false
            if account.userID != nil, terms.hasAccepted {
                do {
                    busyIDs = Set(try await feed.activeAirports(days: 7, limit: 30).map(\.airportID))
                } catch {
                    failed = true
                }
            }
            var found: [AirportMarker] = []
            for id in busyIDs.union(ids).sorted() {
                if let airport = try? await database.airport(id: id) {
                    found.append(AirportMarker(airport: airport, busy: busyIDs.contains(id), mine: ids.contains(id)))
                }
            }
            markers = found
        }
    }
}
