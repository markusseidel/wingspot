import Account
import MapKit
import Persistence
import ReferenceData
import SwiftData
import SwiftUI

/// A map of the airports checked in at. The positions come from the downloaded airport data, so it works offline.
struct AirportsMapView: View {
    @Environment(AccountStore.self) private var account
    @Environment(ReferenceDataStore.self) private var referenceData
    @Query private var all: [LocalCheckIn]
    @State private var airports: [Airport] = []
    @State private var isLoading = true

    private struct LoadKey: Hashable {
        let ids: Set<Int>
        let dataVersion: String?
    }

    var body: some View {
        let ids = CheckInStats(all, userID: account.userID).airportIDs
        Group {
            if airports.isEmpty {
                ContentUnavailableView {
                    Label("No airports yet", systemImage: "map")
                } description: {
                    if isLoading {
                        ProgressView()
                    } else if referenceData.database == nil {
                        Text("The map needs the airport data. Open the app once while online.")
                    } else {
                        Text("Airports you spot at or visit appear here.")
                    }
                }
            } else {
                Map {
                    ForEach(airports) { airport in
                        Marker(
                            airport.code,
                            coordinate: CLLocationCoordinate2D(
                                latitude: airport.coordinate.latitude, longitude: airport.coordinate.longitude
                            )
                        )
                    }
                }
            }
        }
        .navigationTitle("Airports map")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: LoadKey(ids: ids, dataVersion: referenceData.database?.dataVersion)) {
            isLoading = true
            defer { isLoading = false }
            guard let database = referenceData.database else {
                airports = []
                return
            }
            var found: [Airport] = []
            for id in ids.sorted() {
                if let airport = try? await database.airport(id: id) { found.append(airport) }
            }
            airports = found
        }
    }
}
