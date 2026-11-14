import Account
import SwiftUI

extension SharingChoice {
    var title: LocalizedStringKey {
        switch self {
        case .private: "Only me"
        case .friends: "Friends"
        case .followers: "Followers"
        case .public: "Everyone"
        }
    }
}

/// The profile setting for who sees new check-ins. It starts as "Only me", so nobody shares by accident.
struct SharingSection: View {
    @Environment(SocialStore.self) private var social
    @Environment(TermsStore.self) private var terms
    @State private var showTerms = false
    @State private var afterTerms: SharingChoice?
    @State private var choice: SharingChoice?
    @State private var pending: SharingChoice?
    @State private var failure: AccountError?
    @State private var loadFailed = false

    var body: some View {
        Section {
            Picker("Share my check-ins", selection: Binding(
                get: { choice ?? .private },
                set: { new in
                    guard new != choice else { return }
                    // Sharing with others needs the community rules first.
                    if new != .private, !terms.hasAccepted { afterTerms = new; showTerms = true } else { pending = new }
                }
            )) {
                ForEach(SharingChoice.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .disabled(choice == nil)
        } footer: {
            if loadFailed {
                Text("Sharing settings need an internet connection.")
            } else {
                Text("Friends are people you follow who follow you back. Followers are people who follow you. Your exact position is never shown to others.")
            }
        }
        .task { await load() }
        .sheet(isPresented: $showTerms) {
            TermsScreen {
                terms.accept()
                showTerms = false
                pending = afterTerms
                afterTerms = nil
            }
        }
        .confirmationDialog(
            "Also change your earlier check-ins?",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible
        ) {
            Button("Only new check-ins") { apply(applyToExisting: false) }
            Button("All check-ins") { apply(applyToExisting: true) }
            Button("Cancel", role: .cancel) { pending = nil }
        }
        .alert("Couldn't complete this", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            if let failure { Text(failure.message) }
        }
    }

    private func load() async {
        do {
            choice = try await social.sharing()
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    private func apply(applyToExisting: Bool) {
        guard let new = pending else { return }
        pending = nil
        Task {
            do {
                try await social.setSharing(new, applyToExisting: applyToExisting)
                choice = new
            } catch {
                failure = (error as? AccountError) ?? .unknown
            }
        }
    }
}
