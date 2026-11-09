import Account
import Persistence
import ReferenceData
import SwiftData
import SwiftUI

/// One aircraft type: your own sightings, what others have lately checked in, and their recent check-ins.
struct TypePageView: View {
    let typeCode: String

    @Environment(AccountStore.self) private var account
    @Environment(FeedStore.self) private var feed
    @Environment(TermsStore.self) private var terms
    @Environment(ReferenceDataStore.self) private var referenceData
    @Query private var all: [LocalCheckIn]
    @State private var type: AircraftType?
    @State private var store: FeedStore?
    @State private var activity: TypeActivity?
    @State private var activityFailed = false

    var body: some View {
        List {
            header
            yourSightings
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
        .navigationTitle(Text(verbatim: typeCode))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: referenceData.database?.dataVersion) {
            type = try? await referenceData.database?.aircraftType(icao: typeCode)
        }
        .task(id: account.userID) {
            guard account.userID != nil, terms.hasAccepted else { return }
            let created = feed.typeStore(for: typeCode)
            store = created
            async let list: Void = created.refresh()
            do {
                activity = try await feed.typeActivity(of: typeCode)
                activityFailed = false
            } catch {
                activityFailed = true
            }
            await list
        }
    }

    private var header: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: typeCode).font(.system(.title2, design: .monospaced, weight: .semibold))
                if let type {
                    Text(verbatim: type.name).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var yourSightings: some View {
        let mine = CheckInStats.counted(all, userID: account.userID).filter { $0.typeICAO == typeCode }
        return Section {
            if let first = mine.map(\.occurredAt).min(), let last = mine.map(\.occurredAt).max() {
                LabeledContent("Your check-ins", value: "\(mine.count)")
                LabeledContent("First time") { Text(first, format: .dateTime.day().month().year()) }
                LabeledContent("Last time") { Text(last, format: .dateTime.day().month().year()) }
            } else {
                Text("You haven't seen this type yet.").foregroundStyle(.secondary)
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
                LabeledContent("Different airports", value: "\(activity.airports)")
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
