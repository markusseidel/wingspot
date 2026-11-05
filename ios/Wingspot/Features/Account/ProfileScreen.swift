import Account
import ReferenceData
import SwiftUI

/// The Profile tab. Stats, collections and the map join it in Milestone 6.
struct ProfileScreen: View {
    @Environment(AccountStore.self) private var account
    @State private var isSigningIn = false
    @State private var isShowingHistory = false

    var body: some View {
        NavigationStack {
            Group {
                switch account.state {
                case .loading:
                    ProgressView()
                case .signedOut:
                    signedOut
                case .signedIn(nil):
                    profileMissing
                case .signedIn(let profile?):
                    ProfileDetailsView(profile: profile)
                }
            }
            .navigationTitle("Profile")
            .navigationDestination(isPresented: $isSigningIn) {
                EmailSignInView()
            }
            .navigationDestination(isPresented: $isShowingHistory) {
                CheckInHistoryView()
            }
        }
        .onChange(of: account.state) {
            if case .signedIn = account.state { isSigningIn = false }
        }
    }

    private var signedOut: some View {
        ContentUnavailableView {
            Label("Your profile", systemImage: "person.crop.circle")
        } description: {
            Text("Sign in to keep your check-ins safe and follow other spotters. Your check-ins stay on this iPhone until then.")
        } actions: {
            Button("Sign in with email") { isSigningIn = true }
                .buttonStyle(.borderedProminent)
            Button("Check-in history") { isShowingHistory = true }
        }
    }

    private var profileMissing: some View {
        ContentUnavailableView {
            Label("Couldn't load your profile", systemImage: "wifi.slash")
        } description: {
            Text("Check your connection and try again. You can still check in.")
        } actions: {
            Button("Try again") {
                Task { await account.reloadProfile() }
            }
            Button("Check-in history") { isShowingHistory = true }
        }
    }
}

private struct ProfileDetailsView: View {
    let profile: Profile

    @Environment(AccountStore.self) private var account
    @Environment(ReferenceDataStore.self) private var referenceData
    @State private var airport: Airport?
    @State private var signOutFailed = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Username") { Text(verbatim: "@\(profile.username)") }
                if let name = profile.displayName {
                    LabeledContent("Name") { Text(verbatim: name) }
                }
                if let airport {
                    LabeledContent("Home airport") { Text(verbatim: "\(airport.code) · \(airport.name)") }
                }
            }
            Section {
                NavigationLink("Check-in history") {
                    CheckInHistoryView()
                }
                NavigationLink("Edit profile") {
                    ProfileEditorView(profile: profile, isFirstSetup: false)
                }
            }
            Section {
                Button("Sign out", role: .destructive, action: signOut)
            } footer: {
                Text("Your check-ins stay on this iPhone.")
            }
        }
        .task(id: AirportKey(id: profile.homeAirportID, dataVersion: referenceData.database?.dataVersion)) {
            guard let id = profile.homeAirportID, let database = referenceData.database else {
                airport = nil
                return
            }
            airport = try? await database.airport(id: id)
        }
        .alert("Couldn't sign out", isPresented: $signOutFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try again.")
        }
    }

    private func signOut() {
        Task {
            do {
                try await account.signOut()
            } catch {
                signOutFailed = true
            }
        }
    }

    private struct AirportKey: Hashable {
        let id: Int?
        let dataVersion: String?
    }
}
