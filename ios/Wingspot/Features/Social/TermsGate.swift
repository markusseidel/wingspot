import Account
import Persistence
import SwiftUI

/// The community rules, shown once before the social features are used (App Store guideline 1.2). Accounts are for people 16 and
/// older (docs/MINIMUM-AGE-PLAN.md), so "I agree" waits for "I am 16 or older". When this build is too old, it asks for an update.
struct TermsScreen: View {
    let onAccept: () -> Void

    @Environment(TermsStore.self) private var terms
    @State private var isOldEnough = false
    @State private var isShowingYounger = false

    var body: some View {
        if terms.updateRequired {
            UpdateScreen()
        } else {
            rules
        }
    }

    private var rules: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "person.2.wave.2")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Community rules").font(.title.bold())
                Text("Wingspotted is for people who love aircraft. To keep it friendly, please agree to these rules before you follow people, see the feed, or share your check-ins.")
                VStack(alignment: .leading, spacing: 10) {
                    rule("Be respectful. No harassment, hate or threats.")
                    rule("Post only what you may share: no illegal content and no one else's private information.")
                    rule("No spam or advertising.")
                    rule("You're responsible for what you post. Comments with insults are refused automatically.")
                }
                Text("You can report a person, check-in or comment, and block anyone. We review reports and may remove content or accounts that break these rules.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Toggle("I am 16 or older", isOn: $isOldEnough)
                    .accessibilityIdentifier("age-confirm")
                Button(action: onAccept) {
                    Text("I agree").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!isOldEnough)
                .accessibilityIdentifier("accept-rules")
                Button("I'm younger than 16") { isShowingYounger = true }
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("younger")
            }
            .padding()
        }
        .sheet(isPresented: $isShowingYounger) { YoungerView() }
    }

    private func rule(_ text: LocalizedStringKey) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "checkmark.circle").foregroundStyle(.tint)
        }
    }
}

/// For someone younger than 16: accounts are not for them, Wingspot without an account is. Nothing about the answer is stored.
private struct YoungerView: View {
    @Environment(AccountStore.self) private var account
    @Environment(PushStore.self) private var push
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var confirmDeleteAgain = false
    @State private var isBusy = false
    @State private var failure: AccountError?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Wingspotted accounts are for people 16 and older. You can keep using Wingspotted without an account: your check-ins stay on this iPhone.")
                    Button(action: signOut) {
                        Text("Sign out").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isBusy)
                    .accessibilityIdentifier("younger-sign-out")
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Text("Delete my account").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(isBusy)
                    .accessibilityIdentifier("younger-delete")
                    Text("Deleting the account also removes its check-ins from this iPhone. Make a backup in Settings first if you want to keep them.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Younger than 16")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Continue", role: .destructive) { confirmDeleteAgain = true }
            } message: {
                Text("Your profile, check-ins, photos, comments and badges are deleted from our servers. Your check-ins on this iPhone are removed too. This can't be undone.")
            }
            .alert("Delete account for good?", isPresented: $confirmDeleteAgain) {
                Button("Delete account", role: .destructive, action: deleteAccount)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("There is no way to get your account back.")
            }
            .alert("Something went wrong", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                if let failure { Text(failure.message) }
            }
        }
    }

    private func signOut() {
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                await push.removeDevice()
                try await account.signOut()
                dismiss()
            } catch {
                failure = (error as? AccountError) ?? .unknown
            }
        }
    }

    private func deleteAccount() {
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let deleted = try await account.deleteAccount()
                try? AccountEraser(context: modelContext).erase(userID: deleted)
                dismiss()
            } catch {
                failure = (error as? AccountError) ?? .unknown
            }
        }
    }
}

/// This build is older than the server's minimum (docs/MINIMUM-AGE-PLAN.md 4a). The logbook keeps working; the social parts wait.
struct UpdateScreen: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "arrow.down.app")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Please update Wingspotted").font(.title.bold())
                Text("This version of Wingspotted is too old for the feed, people and sharing. Your logbook keeps working.")
                Button {
                    // The TestFlight app, or its web page when it isn't installed.
                    openURL(URL(string: "itms-beta://")!) { opened in
                        if !opened { openURL(URL(string: "https://testflight.apple.com")!) }
                    }
                } label: {
                    Text("Update").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("update-app")
            }
            .padding()
        }
    }
}

extension View {
    /// Shows the rules instead of this screen until the signed-in person has agreed.
    func termsGate() -> some View {
        modifier(TermsGate())
    }
}

private struct TermsGate: ViewModifier {
    @Environment(TermsStore.self) private var terms

    func body(content: Content) -> some View {
        if terms.hasAccepted {
            content
        } else {
            TermsScreen { terms.accept() }
        }
    }
}
