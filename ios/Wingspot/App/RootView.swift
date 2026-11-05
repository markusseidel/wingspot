import Account
import Persistence
import SwiftUI

enum AppTab: Hashable {
    case feed, explore, checkIn, badges, profile
}

/// Main navigation (concept §9): five destinations, the center one opens the check-in sheet.
struct RootView: View {
    @State private var selection: AppTab = .feed
    @State private var isCheckInPresented = false
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @Environment(AccountStore.self) private var account
    @Environment(BadgeStore.self) private var badges

    var body: some View {
        TabView(selection: tabSelection) {
            Tab("Feed", systemImage: "list.bullet.rectangle", value: AppTab.feed) {
                PlaceholderScreen(title: "Feed", systemImage: "list.bullet.rectangle",
                                  message: "Check-ins from people you follow will appear here.")
            }
            Tab("Explore", systemImage: "map", value: AppTab.explore) {
                PlaceholderScreen(title: "Explore", systemImage: "map",
                                  message: "Search aircraft, airports and spotters.")
            }
            Tab("Check in", systemImage: "plus.circle.fill", value: AppTab.checkIn) {
                Color.clear
            }
            Tab("Badges", systemImage: "rosette", value: AppTab.badges) {
                BadgesScreen()
            }
            Tab("Profile", systemImage: "person.crop.circle", value: AppTab.profile) {
                ProfileScreen()
            }
        }
        .sheet(isPresented: $isCheckInPresented) {
            CheckInSheet()
        }
        // Signing in is optional, because check-ins work without an account and offline.
        .fullScreenCover(isPresented: .constant(isSetupPresented)) {
            Group {
                if let profile = account.profile, account.needsProfileSetup {
                    NavigationStack {
                        ProfileEditorView(profile: profile, isFirstSetup: true)
                    }
                } else {
                    OnboardingView { hasSeenOnboarding = true }
                }
            }
            .signInLinkAlert(isEnabled: true)
        }
        .signInLinkAlert(isEnabled: !isSetupPresented)
        // One sheet at a time: the celebration waits until the check-in sheet and the setup screens are gone.
        .sheet(isPresented: .constant(!badges.celebrations.isEmpty && !isCheckInPresented && !isSetupPresented)) {
            CelebrationView(celebrations: badges.celebrations) { badges.acknowledge() }
                .presentationDetents([.large])
                .interactiveDismissDisabled()
        }
        .onChange(of: account.state) {
            if case .signedIn = account.state { hasSeenOnboarding = true }
        }
    }

    private var isSetupPresented: Bool {
        account.needsProfileSetup || (account.state == .signedOut && !hasSeenOnboarding)
    }

    /// Selecting the check-in tab presents the sheet instead of switching tabs.
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selection },
            set: { newValue in
                if newValue == .checkIn {
                    isCheckInPresented = true
                } else {
                    selection = newValue
                }
            }
        )
    }
}
