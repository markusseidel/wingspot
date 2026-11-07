import Account
import SwiftUI

/// The community rules, shown once before the social features are used (App Store guideline 1.2).
struct TermsScreen: View {
    let onAccept: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "person.2.wave.2")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Community rules").font(.title.bold())
                Text("Wingspot is for people who love aircraft. To keep it friendly, please agree to these rules before you follow people, see the feed, or share your check-ins.")
                VStack(alignment: .leading, spacing: 10) {
                    rule("Be respectful. No harassment, hate or threats.")
                    rule("Post only what you may share: no illegal content and no one else's private information.")
                    rule("No spam or advertising.")
                    rule("You're responsible for what you post. Comments with insults are refused automatically.")
                }
                Text("You can report a person, check-in or comment, and block anyone. We review reports and may remove content or accounts that break these rules.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(action: onAccept) {
                    Text("I agree").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
        }
    }

    private func rule(_ text: LocalizedStringKey) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "checkmark.circle").foregroundStyle(.tint)
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
