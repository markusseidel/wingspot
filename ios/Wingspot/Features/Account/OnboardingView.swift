import SwiftUI

/// Shown once on first launch. Asks for nothing yet: location is requested when a check-in needs it.
struct OnboardingView: View {
    let onSkip: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TabView {
                    page("Log every aircraft", systemImage: "binoculars.fill",
                         message: "Enter a registration and see if it's new to you. It works offline too.")
                    page("Earn badges", systemImage: "rosette",
                         message: "Collect aircraft types, airlines and airports as you go.")
                    page("Spot with friends", systemImage: "person.2.fill",
                         message: "Follow other spotters and share what you've seen.")
                }
                .tabViewStyle(.page)
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                VStack(spacing: 12) {
                    AppleSignInButton()
                    NavigationLink {
                        EmailSignInView()
                    } label: {
                        Text("Sign in with email").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button(action: onSkip) {
                        Text("Not now").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
                .padding(.horizontal)
            }
            .padding(.bottom)
        }
    }

    private func page(_ title: LocalizedStringKey, systemImage: String, message: LocalizedStringKey) -> some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title).font(.title.bold())
            Text(message)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(32)
    }
}
