import Account
import SwiftUI

/// The Feed tab: your check-ins and those of the people you follow, newest first.
struct FeedScreen: View {
    @Environment(AccountStore.self) private var account
    @Environment(FeedStore.self) private var feed
    @State private var commentsFor: FeedItem?

    var body: some View {
        NavigationStack {
            Group {
                if account.userID == nil {
                    ContentUnavailableView {
                        Label("Your feed", systemImage: "list.bullet.rectangle")
                    } description: {
                        Text("Sign in from the Profile tab to see check-ins from people you follow.")
                    }
                } else if !feed.hasLoaded {
                    if let failure = feed.failure {
                        ContentUnavailableView {
                            Label("Couldn't load your feed", systemImage: "wifi.slash")
                        } description: {
                            Text(failure.message)
                        } actions: {
                            Button("Try again") { Task { await feed.refresh() } }
                        }
                    } else {
                        ProgressView()
                    }
                } else if feed.items.isEmpty {
                    ContentUnavailableView {
                        Label("Your feed is empty", systemImage: "list.bullet.rectangle")
                    } description: {
                        Text("Check-ins from you and the people you follow appear here. Your check-ins show once they are uploaded and shared.")
                    } actions: {
                        NavigationLink("Find people") { PeopleView() }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Feed")
            .navigationDestination(item: $commentsFor) { CommentsView(item: $0) }
            .toolbar {
                if account.userID != nil {
                    NavigationLink { PeopleView() } label: {
                        Image(systemName: "person.badge.plus")
                    }
                    .accessibilityLabel("Find people")
                }
            }
        }
        .task(id: account.userID) {
            if account.userID == nil {
                feed.clear()
            } else {
                await feed.refresh()
            }
        }
    }

    private var list: some View {
        List {
            if let failure = feed.failure {
                Label(failure.message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(feed.items) { item in
                FeedCard(
                    item: item, isOwn: item.userID == account.userID,
                    onSalute: { Task { await feed.toggleSalute(item.id) } },
                    onComments: { commentsFor = item }
                )
                    .task {
                        // Close to the end: ask for older check-ins.
                        if item.id == feed.items.dropLast(5).last?.id || item.id == feed.items.last?.id {
                            await feed.loadMore()
                        }
                    }
            }
            if feed.isLoading {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .refreshable { await feed.refresh() }
    }
}

private struct FeedCard: View {
    let item: FeedItem
    let isOwn: Bool
    let onSalute: () -> Void
    let onComments: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                if isOwn {
                    Text("You").font(.subheadline.bold())
                } else {
                    NavigationLink { PersonLoaderView(id: item.userID) } label: {
                        Text(verbatim: item.displayName ?? item.username).font(.subheadline.bold())
                    }
                }
                Spacer()
                Text(item.occurredAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Label(kindTitle, systemImage: kindSymbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(verbatim: title)
                .font(.system(.title3, design: .monospaced, weight: .semibold))
            if let detail {
                Text(verbatim: detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 20) {
                Button(action: onSalute) {
                    Label("\(item.salutes)", systemImage: item.saluted ? "hands.clap.fill" : "hands.clap")
                }
                .accessibilityLabel(item.saluted ? "Remove your salute. Salutes: \(item.salutes)" : "Salute. Salutes: \(item.salutes)")
                Button(action: onComments) {
                    Label("\(item.comments)", systemImage: "bubble.left")
                }
                .accessibilityLabel("Comments: \(item.comments)")
            }
            .font(.subheadline)
            .buttonStyle(.borderless)
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }

    private var kindTitle: LocalizedStringKey {
        switch item.kind {
        case "flown": "Flown"
        case "airport": "Airport"
        default: "Spotted"
        }
    }

    private var kindSymbol: String {
        switch item.kind {
        case "flown": "airplane"
        case "airport": "building.columns"
        default: "binoculars"
        }
    }

    /// The registration if there is one, otherwise the type. A flight shows its route.
    private var title: String {
        switch item.kind {
        case "airport": return item.airportCode ?? "?"
        case "flown": return "\(item.originCode ?? "?") → \(item.destinationCode ?? "?")"
        default: return item.registration ?? item.typeICAO ?? "?"
        }
    }

    private var detail: String? {
        switch item.kind {
        case "airport":
            return nil
        case "flown":
            let distance = item.distanceKm.map { "\($0.formatted()) km" }
            let parts = [item.flightNumber, item.registration ?? item.typeName, distance].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        default:
            let parts = [item.typeName ?? (item.registration == nil ? nil : item.typeICAO), item.airportCode].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }
}

/// Opens a person's page from just their ID, as in the feed.
struct PersonLoaderView: View {
    let id: UUID

    @Environment(SocialStore.self) private var social
    @State private var person: Person?
    @State private var failed = false

    var body: some View {
        Group {
            if let person {
                PersonDetailView(person: person)
            } else if failed {
                ContentUnavailableView("Couldn't load this profile", systemImage: "person.crop.circle.badge.questionmark")
            } else {
                ProgressView()
            }
        }
        .task {
            if let loaded = try? await social.person(id) { person = loaded } else { failed = true }
        }
    }
}
