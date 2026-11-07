import Account
import SwiftUI

/// The check-ins of one person that you may see, on their page.
struct PersonCheckInsSection: View {
    let person: Person

    @Environment(AccountStore.self) private var account
    @Environment(FeedStore.self) private var feed
    @State private var store: FeedStore?

    var body: some View {
        Section {
            if let store {
                if store.items.isEmpty {
                    if store.isLoading || !store.hasLoaded {
                        if let failure = store.failure {
                            Label(failure.message, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                        } else {
                            ProgressView().frame(maxWidth: .infinity)
                        }
                    } else {
                        Text(person.isPrivate && !person.isFriend ? "This profile is private." : "No check-ins to show.")
                            .foregroundStyle(.secondary)
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
            Text("Check-ins")
        }
        .task(id: person.id) {
            let created = feed.personStore(for: person.id)
            store = created
            await created.refresh()
        }
    }
}

/// One card with its own comments screen and report sheet.
private struct PersonCheckInRow: View {
    let item: FeedItem
    let store: FeedStore
    let isOwn: Bool

    @State private var commentsFor: FeedItem?
    @State private var report: ReportTarget?

    var body: some View {
        FeedCard(
            item: item, isOwn: isOwn, photos: store.photos[item.id] ?? [],
            onSalute: { Task { await store.toggleSalute(item.id) } },
            onComments: { commentsFor = item },
            onReport: { report = ReportTarget(kind: .checkin, id: item.id, subject: "this check-in") },
            onReportPhoto: { report = ReportTarget(kind: .photo, id: $0.id, subject: "this photo") }
        )
        .navigationDestination(item: $commentsFor) { CommentsView(item: $0, source: store) }
        .sheet(item: $report) { ReportSheet(target: $0) }
    }
}
