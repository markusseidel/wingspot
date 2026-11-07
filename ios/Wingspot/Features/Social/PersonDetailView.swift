import Account
import SwiftUI

/// Someone's profile, with follow and block.
struct PersonDetailView: View {
    @State var person: Person

    @Environment(SocialStore.self) private var social
    @Environment(\.dismiss) private var dismiss
    @State private var isWorking = false
    @State private var confirmBlock = false
    @State private var report: ReportTarget?
    @State private var failure: AccountError?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: person.displayName ?? person.username).font(.title2.bold())
                    Text(verbatim: "@\(person.username)").foregroundStyle(.secondary)
                    if person.isPrivate {
                        Label("Private profile", systemImage: "lock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if person.followsYou {
                        Text(person.isFriend ? "Friends" : "Follows you")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Section {
                if person.isFollowing {
                    Button("Unfollow", role: .destructive) { change { try await social.unfollow(person.id) } }
                } else {
                    Button("Follow") { change { try await social.follow(person.id) } }
                }
            }
            .disabled(isWorking)
            PersonCheckInsSection(person: person)
            Section {
                Button("Report") {
                    report = ReportTarget(kind: .user, id: person.id, subject: "@\(person.username)")
                }
                Button("Block", role: .destructive) { confirmBlock = true }
                    .disabled(isWorking)
            }
        }
        .navigationTitle(Text(verbatim: "@\(person.username)"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $report) { ReportSheet(target: $0) }
        .confirmationDialog(
            Text("Block @\(person.username)?"), isPresented: $confirmBlock, titleVisibility: .visible
        ) {
            Button("Block", role: .destructive) { block() }
        } message: {
            Text("You won't see each other's check-ins or comments anymore, and any follows between you end.")
        }
        .alert("Couldn't complete this", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            if let failure { Text(failure.message) }
        }
    }

    /// Runs a change, then looks the person up again so the buttons match the server.
    private func change(_ work: @escaping () async throws -> Void) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await work()
                if let fresh = try await social.person(person.id) { person = fresh }
            } catch {
                failure = (error as? AccountError) ?? .unknown
            }
        }
    }

    private func block() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await social.block(person.id)
                dismiss()
            } catch {
                failure = (error as? AccountError) ?? .unknown
            }
        }
    }
}
