import Account
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
    @Environment(PushRouter.self) private var router

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
            } else if inbox.items.isEmpty {
                ContentUnavailableView {
                    Label("Nothing yet", systemImage: "bell")
                } description: {
                    Text("New followers, salutes, comments and tags show up here.")
                }
            } else {
                List {
                    ForEach(inbox.items) { item in
                        Button { open(item) } label: { InboxRow(item: item) }
                            .buttonStyle(.plain)
                            .disabled(destination(of: item) == nil)
                            .listRowBackground(item.isRead ? nil : Color.accentColor.opacity(0.08))
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
        .task { await inbox.load() }
        .refreshable { await inbox.load() }
    }

    private func destination(of item: ActivityItem) -> PushDestination? {
        if item.kind == "follow" { return .person(item.actorID) }
        if let id = item.checkInID { return .checkIn(id) }
        return nil
    }

    /// The feed screen opens what the router points at, the same way as for a tapped push notification.
    private func open(_ item: ActivityItem) {
        router.destination = destination(of: item)
    }
}

private struct InboxRow: View {
    let item: ActivityItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(id: item.actorID, name: item.who, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)
                if let quote = item.snippet, !quote.isEmpty, item.kind == "comment" {
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
        default:
            return bold(String(localized: "\(name) has news for you"), name)
        }
    }

    private func bold(_ sentence: String, _ name: String) -> AttributedString {
        var text = AttributedString(sentence)
        if let range = text.range(of: name) { text[range].font = .subheadline.bold() }
        return text
    }
}
