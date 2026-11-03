import SwiftUI

enum AppTab: Hashable {
    case feed, explore, checkIn, badges, profile
}

/// Main navigation (concept §9): five destinations, the center one opens the check-in sheet.
struct RootView: View {
    @State private var selection: AppTab = .feed
    @State private var isCheckInPresented = false

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
                PlaceholderScreen(title: "Badges", systemImage: "rosette",
                                  message: "Earn badges for the aircraft you spot and fly.")
            }
            Tab("Profile", systemImage: "person.crop.circle", value: AppTab.profile) {
                PlaceholderScreen(title: "Profile", systemImage: "person.crop.circle",
                                  message: "Your stats, collection and map.")
            }
        }
        .sheet(isPresented: $isCheckInPresented) {
            CheckInSheet()
        }
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

#Preview {
    RootView()
}
