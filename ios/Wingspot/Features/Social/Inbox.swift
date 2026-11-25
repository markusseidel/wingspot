import Account
import Persistence
import SwiftData
import SwiftUI

/// The activity inbox: followers, salutes, comments, tags and alerts, newest first, and how many are unread.
@MainActor
@Observable
final class InboxStore {
    private let backend: any ActivityBackend
    private let pageSize = 30

    private(set) var items: [ActivityItem] = []
    /// Unread, up to 99. Drives the dot on the bell.
    private(set) var unread = 0
    private(set) var hasLoaded = false
    private(set) var hasMore = false
    private(set) var failed = false

    init(backend: any ActivityBackend) {
        self.backend = backend
    }

    func refreshCount() async {
        if let count = try? await backend.unreadActivityCount() { unread = count }
    }

    /// Loads the first page. Nothing is marked read by looking: the person does that with "Mark all read".
    func load() async {
        do {
            let page = try await backend.activity(before: nil, limit: pageSize)
            items = page
            hasMore = page.count >= pageSize
            failed = false
            hasLoaded = true
            await refreshCount()
        } catch {
            failed = true
            hasLoaded = true
        }
    }

    func loadMore() async {
        guard hasMore, let last = items.last else { return }
        guard let page = try? await backend.activity(before: last.createdAt, limit: pageSize) else { return }
        let known = Set(items.map(\.id))
        items += page.filter { !known.contains($0.id) }
        hasMore = page.count >= pageSize
    }

    var hasUnread: Bool { unread > 0 || items.contains { !$0.isRead } }

    func markAllRead() async {
        let before = (items, unread)
        for index in items.indices { items[index].isRead = true }
        unread = 0
        do {
            try await backend.markActivityRead()
        } catch {
            (items, unread) = before
        }
    }

    /// Opening a row marks it read. The row and the count change at once, and go back if the server says no.
    func markRead(_ item: ActivityItem) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }), !items[index].isRead else { return }
        items[index].isRead = true
        let wasUnread = unread
        unread = max(unread - 1, 0)
        do {
            try await backend.markActivityRead(id: item.id)
        } catch {
            if let back = items.firstIndex(where: { $0.id == item.id }) { items[back].isRead = false }
            unread = wasUnread
        }
    }

    func clear() {
        items = []
        unread = 0
        hasLoaded = false
        hasMore = false
        failed = false
    }
}

struct InboxView: View {
    @Environment(InboxStore.self) private var inbox
    @Environment(FeedStore.self) private var feed
    /// What was tapped opens from this screen, so Back comes back here and not to the feed.
    @State private var openedCheckIn: FeedItem?
    @State private var openedPerson: OpenedPerson?
    @State private var showPlaceReview = false
    /// Taking over a friend's flight (#273).
    @State private var companion = CompanionFlow()
    @Environment(\.modelContext) private var modelContext
    @Environment(AccountStore.self) private var account
    @Environment(CheckInSyncCoordinator.self) private var sync: CheckInSyncCoordinator?

    private struct OpenedPerson: Identifiable, Hashable { let id: UUID }

    var body: some View {
        Group {
            if !inbox.hasLoaded {
                ProgressView()
            } else if inbox.failed && inbox.items.isEmpty {
                ContentUnavailableView {
                    Label("Couldn't load your activity", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Please check your connection and try again.")
                } actions: {
                    Button("Try again") { Task { await inbox.load() } }
                }
            } else if inbox.items.isEmpty && feed.companionRequests.isEmpty {
                ContentUnavailableView {
                    Label("Nothing yet", systemImage: "bell")
                } description: {
                    Text("New followers, salutes, comments and tags show up here.")
                }
            } else {
                List {
                    if !feed.companionRequests.isEmpty {
                        Section {
                            ForEach(feed.companionRequests) { request in
                                CompanionRequestRow(request: request, onAccept: { accept(request) }, onDecline: { decline(request) })
                            }
                        } header: {
                            Text("Flights to take over")
                        }
                    }
                    ForEach(inbox.items) { item in
                        Button { open(item) } label: { InboxRow(item: item) }
                            .buttonStyle(.plain)
                            .listRowBackground(item.isRead ? nil : Color.accentColor.opacity(0.2))
                            .onAppear {
                                if item.id == inbox.items.last?.id { Task { await inbox.loadMore() } }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Mark all read") { Task { await inbox.markAllRead() } }
                    .disabled(!inbox.hasUnread)
            }
        }
        .navigationDestination(item: $openedCheckIn) { CheckInDetailView(item: $0) }
        .navigationDestination(item: $openedPerson) { PersonLoaderView(id: $0.id) }
        .navigationDestination(isPresented: $showPlaceReview) { SpotReviewView() }
        .task {
            await inbox.load()
            await feed.loadCompanionRequests()
        }
        .refreshable {
            await inbox.load()
            await feed.loadCompanionRequests()
        }
        .companionAsk(companion) { choice, ask in
            Task { await companion.choose(choice, for: ask, feed: feed, context: modelContext, userID: account.userID, sync: sync) }
        }
    }

    /// "Add to my logbook" on a request: the friend's check-in is asked for by id, because it may be someone else's and not in the feed.
    private func accept(_ request: CompanionRequest) {
        Task {
            var found = feed.items.first(where: { $0.id == request.checkInID })
            if found == nil { found = await feed.checkIn(request.checkInID) }
            guard let item = found else {
                companion.problem = .unknown
                return
            }
            await companion.accept(item, feed: feed, context: modelContext, userID: account.userID, sync: sync)
        }
    }

    /// "Not me": leaves the check-in for good, like "Remove me from this check-in".
    private func decline(_ request: CompanionRequest) {
        Task {
            if await feed.removeMyTag(request.checkInID) { feed.requestAnswered(request.checkInID) } else { companion.problem = feed.failure ?? .unknown }
        }
    }

    private func destination(of item: ActivityItem) -> PushDestination? {
        if item.kind == "follow" { return .person(item.actorID) }
        if item.kind == "spot_proposed" { return .reviewPlaces }
        if let id = item.checkInID { return .checkIn(id) }
        return nil
    }

    private func open(_ item: ActivityItem) {
        Task { await inbox.markRead(item) }
        switch destination(of: item) {
        case .person(let id):
            openedPerson = OpenedPerson(id: id)
        case .checkIn(let id):
            // It may be older than the pages loaded, or someone else's, so it is asked for by id.
            Task {
                if let known = feed.items.first(where: { $0.id == id }) {
                    openedCheckIn = known
                } else {
                    openedCheckIn = await feed.checkIn(id)
                }
            }
        case .reviewPlaces:
            showPlaceReview = true
        case nil:
            break
        }
    }
}

private struct InboxRow: View {
    let item: ActivityItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // A dot for what is unread: a tint alone is hard to see in dark mode.
            Circle()
                .fill(item.isRead ? Color.clear : Color.accentColor)
                .frame(width: 8, height: 8)
                .padding(.top, 16)
                .accessibilityHidden(true)
            AvatarView(id: item.actorID, name: item.who, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)
                if item.kind == "spot_rejected", let reason {
                    Text(verbatim: reason).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
                }
                if let quote = item.snippet, !quote.isEmpty, (item.kind == "comment" || item.kind == "mention") {
                    Text("“\(quote)”")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(item.createdAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }

    /// One sentence that starts with who did it. The name is part of the text so it reads right in German too.
    private var text: AttributedString {
        let name = item.who
        let subject = item.subject
        switch item.kind {
        case "follow":
            return bold(String(localized: "\(name) started following you"), name)
        case "salute":
            if let subject { return bold(String(localized: "\(name) saluted your check-in \(subject)"), name) }
            return bold(String(localized: "\(name) saluted your check-in"), name)
        case "comment":
            if let subject { return bold(String(localized: "\(name) commented on \(subject)"), name) }
            return bold(String(localized: "\(name) commented on your check-in"), name)
        case "tagged":
            if let subject { return bold(String(localized: "\(name) tagged you on \(subject)"), name) }
            return bold(String(localized: "\(name) tagged you on a check-in"), name)
        case "checkin":
            if let subject { return bold(String(localized: "\(name) checked in \(subject)"), name) }
            return bold(String(localized: "\(name) has a new check-in"), name)
        case "tag_copy":
            if let subject { return bold(String(localized: "\(name) added your flight \(subject) to their logbook"), name) }
            return bold(String(localized: "\(name) added your check-in to their logbook"), name)
        case "mention":
            return bold(String(localized: "\(name) mentioned you in a comment"), name)
        case "comment_like":
            return bold(String(localized: "\(name) saluted your comment"), name)
        case "spot_proposed":
            let place = place
            return bold(String(localized: "\(name) suggested a place: \(place)"), name)
        case "spot_approved":
            let place = place
            return bold(String(localized: "Your place \(place) is now live"), place)
        case "spot_rejected":
            let place = place
            return bold(String(localized: "Your place \(place) was not accepted"), place)
        default:
            return bold(String(localized: "\(name) has news for you"), name)
        }
    }

    /// The name of the place in a decision notice: the first line of the snippet. A reason follows on the next lines.
    private var place: String { (item.snippet ?? "").split(separator: "\n", maxSplits: 1).first.map(String.init) ?? "" }
    private var reason: String? {
        let parts = (item.snippet ?? "").split(separator: "\n", maxSplits: 1)
        return parts.count > 1 ? String(parts[1]) : nil
    }

    private func bold(_ sentence: String, _ name: String) -> AttributedString {
        var text = AttributedString(sentence)
        if let range = text.range(of: name) { text[range].font = .subheadline.bold() }
        return text
    }
}

/// One open request in the inbox: a friend's flight or visit you are tagged on, with the two answers.
private struct CompanionRequestRow: View {
    let request: CompanionRequest
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: request.who).font(.subheadline.weight(.semibold))
            Text(verbatim: details).font(.headline)
            HStack {
                Button("Add to my logbook", action: onAccept).buttonStyle(.borderedProminent)
                Button("Not me", role: .destructive, action: onDecline).buttonStyle(.bordered)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }

    private var details: String {
        var parts = [request.title]
        if let number = request.flightNumber { parts.append(number) }
        parts.append(request.occurredAt.formatted(date: .abbreviated, time: .omitted))
        return parts.joined(separator: " · ")
    }
}
