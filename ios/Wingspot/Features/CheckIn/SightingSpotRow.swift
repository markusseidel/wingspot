import Account
import SwiftUI

/// The spotting location of a sighting: a picker with the places of the sighting's airport, "None" by default. Not shown when signed out, without
/// an airport, with no place at that airport, or while a spotting session runs (the session has the place, `inSession`).
struct SightingSpotRow: View {
    let airportID: Int?
    var inSession = false
    @Binding var choice: SpotLocation?
    /// True once the places of the airport were read, so an edit knows whether "None" was a real choice.
    @Binding var loaded: Bool

    @Environment(AccountStore.self) private var account
    @Environment(SpotStore.self) private var spots
    @State private var places: [SpotLocation] = []

    var body: some View {
        Group {
            if !inSession, !places.isEmpty {
                Picker("Spotting location", selection: Binding(
                    get: { choice?.id },
                    set: { id in choice = places.first { $0.id == id } }
                )) {
                    Text("None").tag(Int?.none)
                    ForEach(places) { Text(verbatim: $0.name).tag(Int?.some($0.id)) }
                }
            }
        }
        .task(id: airportID) {
            guard let airportID, account.userID != nil else { places = []; loaded = false; return }
            let found = await spots.locations(at: airportID)
            places = found
            // An empty answer may be a failed request: then nothing is decided, and an edit leaves the place as it was.
            loaded = !found.isEmpty
            // A place from another airport does not fit this one.
            if loaded, let current = choice, !found.contains(where: { $0.id == current.id }) { choice = nil }
        }
    }
}
