import Account
import Persistence
import ReferenceData
import SwiftData
import SwiftUI

/// The Profile tab. Collections and the map join the stats in Milestone 6.
struct ProfileScreen: View {
    @Environment(AccountStore.self) private var account
    @Query private var all: [LocalCheckIn]
    @State private var isSigningIn = false
    @State private var isShowingHistory = false
    @State private var isShowingCollections = false

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
            .navigationDestination(isPresented: $isShowingCollections) {
                CollectionsView()
            }
        }
        .onChange(of: account.state) {
            if case .signedIn = account.state { isSigningIn = false }
        }
    }

    /// Laid out like the first screen: the text in the middle, the buttons at the bottom, as wide as the screen allows.
    private var signedOut: some View {
        VStack(spacing: 16) {
            Spacer()
            ContentUnavailableView {
                Label("Your profile", systemImage: "person.crop.circle")
            } description: {
                Text("Sign in to keep your check-ins safe and follow other spotters. Your check-ins stay on this iPhone until then.")
            }
            let stats = CheckInStats(all, userID: nil)
            if stats.checkIns > 0 {
                VStack(spacing: 12) { ProfileStatsRows(stats: stats) }
                    .padding()
                    .background(.background.secondary, in: .rect(cornerRadius: 12))
                    .padding(.horizontal)
            }
            Spacer()
            VStack(spacing: 12) {
                AppleSignInButton()
                Button { isSigningIn = true } label: {
                    Text("Sign in with email").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                HStack(spacing: 12) {
                    Button { isShowingCollections = true } label: {
                        Text("Collections").frame(maxWidth: .infinity)
                    }
                    Button { isShowingHistory = true } label: {
                        Text("Check-in history").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .padding(.horizontal)
        }
        .padding(.bottom)
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
    @Environment(BadgeStore.self) private var badges
    @Query private var all: [LocalCheckIn]
    @State private var airport: Airport?
    @State private var signOutFailed = false
    @State private var confirmDelete = false
    @State private var exportFile: SharedFile?
    @State private var exportedURL: URL?
    @State private var isExporting = false
    @State private var exportFailure: AccountError?
    @State private var confirmDeleteAgain = false
    @State private var isDeleting = false
    @State private var deleteFailure: AccountError?
    @Environment(\.modelContext) private var modelContext

    private var stats: CheckInStats { CheckInStats(all, userID: account.userID) }

    var body: some View {
        Form {
            if let progress = badges.progress {
                Section { LevelHeader(progress: progress) }
            }
            Section { ProfileStatsRows(stats: stats) }
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
                NavigationLink("People") { PeopleView() }
                NavigationLink("Collections") { CollectionsView() }
                NavigationLink("Check-in history") {
                    CheckInHistoryView()
                }
                NavigationLink("Edit profile") {
                    ProfileEditorView(profile: profile, isFirstSetup: false)
                }
                NavigationLink("Settings") { SettingsView() }
            }
            Section {
                Button(action: exportData) {
                    if isExporting { ProgressView() } else { Text("Export my data") }
                }
                .disabled(isExporting)
            } footer: {
                Text("A file with your profile, check-ins and everything else we store about you. Photos are listed, not included.")
            }
            Section {
                Button("Sign out", role: .destructive, action: signOut)
            } footer: {
                Text("Your check-ins stay on this iPhone.")
            }
            Section {
                Button("Delete account", role: .destructive) { confirmDelete = true }
                    .disabled(isDeleting)
            } footer: {
                Text("Deletes your account, your check-ins, photos, comments and follows on our servers for good.")
            }
        }
        .sheet(item: $exportFile, onDismiss: removeExportFile) { ShareSheet(file: $0.url) }
        .alert("Couldn't export your data", isPresented: Binding(get: { exportFailure != nil }, set: { if !$0 { exportFailure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            if let exportFailure { Text(exportFailure.message) }
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
        .alert("Couldn't delete your account", isPresented: Binding(get: { deleteFailure != nil }, set: { if !$0 { deleteFailure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            if let deleteFailure { Text(deleteFailure.message) }
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

    private func exportData() {
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                let data = try await account.exportData()
                let name = "wingspot-export-\(Date.now.formatted(.iso8601.year().month().day())).json"
                let url = URL.temporaryDirectory.appending(path: name)
                try data.write(to: url, options: [.atomic, .completeFileProtection])
                exportedURL = url
                exportFile = SharedFile(url: url)
            } catch {
                exportFailure = (error as? AccountError) ?? .unknown
            }
        }
    }

    /// The file holds personal data, so it doesn't stay in the temporary folder.
    private func removeExportFile() {
        guard let exportedURL else { return }
        try? FileManager.default.removeItem(at: exportedURL)
        self.exportedURL = nil
    }

    private func deleteAccount() {
        isDeleting = true
        Task {
            defer { isDeleting = false }
            do {
                let deleted = try await account.deleteAccount()
                try? AccountEraser(context: modelContext).erase(userID: deleted)
            } catch {
                deleteFailure = (error as? AccountError) ?? .unknown
            }
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

/// The five numbers, for a form section or a plain card.
private struct ProfileStatsRows: View {
    let stats: CheckInStats

    var body: some View {
        LabeledContent("Check-ins") { Text(stats.checkIns, format: .number) }
        LabeledContent("Aircraft seen") { Text(stats.aircraft, format: .number) }
        LabeledContent("Aircraft types") { Text(stats.types, format: .number) }
        LabeledContent("Airports") { Text(stats.airports, format: .number) }
        LabeledContent("Flights") { Text(stats.flights, format: .number) }
    }
}
