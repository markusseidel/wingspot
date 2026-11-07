import Account
import SwiftUI
import WingspotCore

extension Int {
    /// What the app offers for the post delay, as words.
    var postDelayTitle: LocalizedStringKey {
        switch self {
        case 0: "No delay"
        case 60: "1 hour"
        case 360: "6 hours"
        case 1440: "24 hours"
        default: "\(self / 60) hours"
        }
    }
}

/// Who sees your check-ins and how distances are shown.
struct SettingsView: View {
    @Environment(SocialStore.self) private var social
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometres
    @State private var settings: PrivacySettings?
    @State private var loadFailed = false
    @State private var failure: AccountError?

    var body: some View {
        Form {
            SharingSection()
            Section {
                Toggle("Private profile", isOn: Binding(
                    get: { settings?.isPrivate ?? false },
                    set: { new in change { $0.isPrivate = new } }
                ))
                Picker("Delay for public check-ins", selection: Binding(
                    get: { settings?.postDelayMinutes ?? 0 },
                    set: { new in change { $0.postDelayMinutes = new } }
                )) {
                    ForEach(delayChoices, id: \.self) { Text($0.postDelayTitle).tag($0) }
                }
            } header: {
                Text("Privacy")
            } footer: {
                if loadFailed {
                    Text("Privacy settings need an internet connection.")
                } else {
                    Text("A private profile shows its details and check-ins only to friends. A delay holds back your public check-ins from strangers for a while, so nobody can tell where you are right now. Friends see them at once.")
                }
            }
            .disabled(settings == nil)
            Section("Units") {
                Picker("Distances", selection: $unit) {
                    ForEach(DistanceUnit.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert("Couldn't complete this", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            if let failure { Text(failure.message) }
        }
    }

    /// The choices, plus the current value if an older version of the app saved another one.
    private var delayChoices: [Int] {
        var choices = PrivacySettings.delayChoices
        if let current = settings?.postDelayMinutes, !choices.contains(current) { choices.append(current) }
        return choices.sorted()
    }

    private func load() async {
        do {
            settings = try await social.privacy()
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    /// Shows the change at once and puts the old values back if the server refuses.
    private func change(_ edit: (inout PrivacySettings) -> Void) {
        guard let before = settings else { return }
        var after = before
        edit(&after)
        guard after != before else { return }
        settings = after
        Task {
            do {
                try await social.setPrivacy(after)
            } catch {
                settings = before
                failure = (error as? AccountError) ?? .unknown
            }
        }
    }
}
