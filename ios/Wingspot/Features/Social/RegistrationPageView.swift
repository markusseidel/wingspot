import Account
import Persistence
import SwiftData
import SwiftUI

/// One aircraft by its registration: your own sightings and the recent check-ins you may see. A sensitive aircraft
/// of someone else gives the same empty page as a registration nobody has seen.
struct RegistrationPageView: View {
    let registration: String

    @Environment(AccountStore.self) private var account
    @Environment(FeedStore.self) private var feed
    @Environment(TermsStore.self) private var terms
    @Query private var all: [LocalCheckIn]
    @State private var store: FeedStore?

    private var normalized: String { Self.normalize(registration) }

    /// Letters and digits only, in capitals: the same rule the server uses to match.
    static func normalize(_ text: String) -> String {
        String(text.uppercased().filter { $0.isLetter || $0.isNumber })
    }

    /// The type of the newest check-in that names one.
    private var typeCode: String? {
        store?.items.compactMap(\.typeICAO).first
    }

    var body: some View {
        List {
            header
            yourSightings
            if account.userID != nil {
                if terms.hasAccepted {
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
        .navigationTitle(Text(verbatim: registration.uppercased()))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: account.userID) {
            guard account.userID != nil, terms.hasAccepted else { return }
            let created = feed.registrationStore(for: registration)
            store = created
            await created.refresh()
        }
    }

    private var header: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: registration.uppercased()).font(.system(.title2, design: .monospaced, weight: .semibold))
                if let typeName = store?.items.compactMap(\.typeName).first {
                    Text(verbatim: typeName).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            if let typeCode {
                NavigationLink { TypePageView(typeCode: typeCode) } label: {
                    LabeledContent("Type") { Text(verbatim: typeCode) }
                }
            }
        }
    }

    private var yourSightings: some View {
        let mine = CheckInStats.counted(all, userID: account.userID).filter { Self.normalize($0.registration ?? "") == normalized }
        return Section {
            if let first = mine.map(\.occurredAt).min(), let last = mine.map(\.occurredAt).max() {
                LabeledContent("Your check-ins", value: "\(mine.count)")
                LabeledContent("First time") { Text(first, format: .dateTime.day().month().year()) }
                LabeledContent("Last time") { Text(last, format: .dateTime.day().month().year()) }
            } else {
                Text("You haven't seen this aircraft yet.").foregroundStyle(.secondary)
            }
        } header: {
            Text("You")
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
        } footer: {
            Text("Only check-ins you are allowed to see are shown.")
        }
    }
}
