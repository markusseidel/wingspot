import Account
import MapKit
import Persistence
import ReferenceData
import SwiftData
import SwiftUI

/// One airport: where it is, your own visits, and what others have recently checked in there.
struct AirportPageView: View {
    let airportID: Int

    @Environment(AccountStore.self) private var account
    @Environment(FeedStore.self) private var feed
    @Environment(TermsStore.self) private var terms
    @Environment(ReferenceDataStore.self) private var referenceData
    @Query private var all: [LocalCheckIn]
    @State private var airport: Airport?
    @State private var store: FeedStore?
    @State private var activity: AirportActivity?
    @State private var activityFailed = false

    var body: some View {
        List {
            header
            yourVisits
            if account.userID != nil {
                if terms.hasAccepted {
                    activitySection
                    recentSection
                } else {
                    Section {
                        Text("Agree to the community rules in the Feed tab to see what others checked in here.")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Section {
                    Text("Sign in from the Profile tab to see what others checked in here.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(Text(verbatim: airport?.code ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: referenceData.database?.dataVersion) {
            airport = try? await referenceData.database?.airport(id: airportID)
        }
        .task(id: account.userID) {
            guard account.userID != nil, terms.hasAccepted else { return }
            let created = feed.airportStore(for: airportID)
            store = created
            async let list: Void = created.refresh()
            do {
                activity = try await feed.airportActivity(at: airportID)
                activityFailed = false
            } catch {
                activityFailed = true
            }
            await list
        }
    }

    @ViewBuilder
    private var header: some View {
        Section {
            if let airport {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: airport.name).font(.title3.bold())
                    let codes = [airport.iata, airport.icao].compactMap { $0 }.joined(separator: " · ")
                    Text(verbatim: [codes, airport.city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — "))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                let center = CLLocationCoordinate2D(latitude: airport.coordinate.latitude, longitude: airport.coordinate.longitude)
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: center, span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)
                )), interactionModes: []) {
                    Marker(airport.code, coordinate: center)
                }
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .accessibilityHidden(true)
            } else if referenceData.database == nil {
                Text("The airport data isn't on this iPhone yet. Open the app once while online.")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
    }

    private var yourVisits: some View {
        let mine = CheckInStats.counted(all, userID: account.userID)
            .filter { $0.airportID == airportID && $0.kind != "flown" }
        return Section {
            if let last = mine.map(\.occurredAt).max() {
                LabeledContent("Your check-ins", value: "\(mine.count)")
                LabeledContent("Last time") { Text(last, format: .dateTime.day().month().year()) }
            } else {
                Text("You haven't checked in here yet.").foregroundStyle(.secondary)
            }
        } header: {
            Text("You")
        }
    }

    @ViewBuilder
    private var activitySection: some View {
        Section {
            if let activity {
                LabeledContent("Check-ins, last 30 days", value: "\(activity.checkIns)")
                LabeledContent("Different aircraft", value: "\(activity.aircraft)")
                ForEach(activity.topSpotters) { spotter in
                    if spotter.userID == account.userID {
                        LabeledContent("You", value: "\(spotter.checkIns)×")
                    } else {
                        NavigationLink {
                            PersonLoaderView(id: spotter.userID)
                        } label: {
                            LabeledContent {
                                Text(verbatim: "\(spotter.checkIns)×")
                            } label: {
                                Text(verbatim: spotter.displayName ?? spotter.username)
                            }
                        }
                    }
                }
            } else if activityFailed {
                Label("Couldn't load this. Check your connection.", systemImage: "wifi.slash").foregroundStyle(.secondary)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        } header: {
            Text("Activity")
        } footer: {
            Text("Counts include only check-ins you are allowed to see.")
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        Section {
            if let store {
                if store.items.isEmpty {
                    if let failure = store.failure {
                        Label(failure.message, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                    } else if store.hasLoaded {
                        Text("Nothing to show yet.").foregroundStyle(.secondary)
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                }
                ForEach(store.items) { item in
                    PersonCheckInRow(item: item, store: store, isOwn: item.userID == account.userID)
                        .task {
                            if item.id == store.items.last?.id { await store.loadMore() }
                        }
                }
            }
        } header: {
            Text("Recent check-ins")
        }
    }
}
