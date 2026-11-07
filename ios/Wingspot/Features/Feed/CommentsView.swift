import Account
import SwiftUI

/// The comments under one check-in, with a field to write a new one.
struct CommentsView: View {
    let item: FeedItem
    /// The list the check-in comes from, so its comment count follows. The Feed tab's list if `nil`.
    var source: FeedStore?

    @Environment(AccountStore.self) private var account
    @Environment(FeedStore.self) private var feed
    @State private var store: CheckInCommentStore?
    @State private var text = ""
    @State private var problem: AccountError?
    @State private var report: ReportTarget?

    var body: some View {
        Group {
            if let store {
                content(store)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Comments")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let created = (source ?? feed).commentStore(for: item.id)
            store = created
            await created.load()
        }
    }

    private func content(_ store: CheckInCommentStore) -> some View {
        List {
            if store.isLoading, !store.hasLoaded {
                ProgressView().frame(maxWidth: .infinity)
            } else if let failure = store.failure, !store.hasLoaded {
                Text(failure.message).foregroundStyle(.secondary)
            } else if store.comments.isEmpty {
                Text("No comments yet").foregroundStyle(.secondary)
            }
            ForEach(store.comments) { comment in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: comment.displayName ?? comment.username).font(.subheadline.bold())
                        Spacer()
                        Text(comment.createdAt, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(verbatim: comment.body)
                }
                .accessibilityElement(children: .combine)
                .swipeActions {
                    // Your own comments, and any comment under your own check-in.
                    if comment.userID == account.userID || item.userID == account.userID {
                        Button("Delete", role: .destructive) { Task { await store.delete(comment) } }
                    }
                    if comment.userID != account.userID {
                        Button("Report") {
                            report = ReportTarget(kind: .comment, id: comment.id, subject: "this comment")
                        }
                        .tint(.orange)
                    }
                }
            }
        }
        .refreshable { await store.load() }
        .sheet(item: $report) { ReportSheet(target: $0) }
        .safeAreaInset(edge: .bottom) { composer(store) }
        .alert("Couldn't complete this", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            if let problem { Text(problem.message) }
        }
    }

    private func composer(_ store: CheckInCommentStore) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Write a comment…", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
            Button {
                send(store)
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .accessibilityLabel("Send")
            .disabled(!CheckInCommentStore.isSendable(text) || store.isSending)
        }
        .padding()
        .background(.bar)
    }

    private func send(_ store: CheckInCommentStore) {
        let draft = text
        Task {
            do {
                try await store.send(draft)
                text = ""
            } catch {
                problem = (error as? AccountError) ?? .unknown
            }
        }
    }
}
