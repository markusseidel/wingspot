import Account
import ReferenceData
import SwiftUI

/// Sets the username, name and home airport, right after the first sign-in and later from the profile.
struct ProfileEditorView: View {
    let profile: Profile
    let isFirstSetup: Bool

    @Environment(AccountStore.self) private var account
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss

    @State private var username: String
    @State private var displayName: String
    @State private var airport: Airport?
    @State private var homeAirportID: Int?
    @State private var isSaving = false
    @State private var error: LocalizedStringResource?

    init(profile: Profile, isFirstSetup: Bool) {
        self.profile = profile
        self.isFirstSetup = isFirstSetup
        // A generated username is no use as a starting point.
        _username = State(initialValue: profile.hasChosenUsername ? profile.username : "")
        _displayName = State(initialValue: profile.displayName ?? "")
        _homeAirportID = State(initialValue: profile.homeAirportID)
    }

    private var normalizedUsername: String { Username.normalized(username) }

    var body: some View {
        Form {
            Section {
                TextField("Username", text: $username)
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Username")
            } footer: {
                if let error {
                    Text(error).foregroundStyle(.red)
                } else {
                    Text("3 to 30 lowercase letters, numbers or underscores.")
                }
            }

            Section {
                TextField("Name", text: $displayName)
                    .textContentType(.name)
            } header: {
                Text("Name")
            } footer: {
                Text("Optional. Shown on your profile.")
            }

            Section {
                NavigationLink {
                    AirportSearchView(selection: Binding(
                        get: { airport },
                        set: {
                            airport = $0
                            homeAirportID = $0?.id
                        }
                    ))
                } label: {
                    LabeledContent("Home airport", value: airportLabel)
                }
            } footer: {
                Text("Optional. Shown on your profile.")
            }
        }
        .navigationTitle(isFirstSetup ? "Create your profile" : "Edit profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(isSaving || !Username.isValid(normalizedUsername))
            }
        }
        .task(id: referenceData.database?.dataVersion) { await loadAirport() }
    }

    private var airportLabel: String {
        if let airport { return "\(airport.code) · \(airport.name)" }
        // The airport is set, but the reference data isn't on this device yet.
        return homeAirportID == nil ? String(localized: "None") : String(localized: "Set")
    }

    private func loadAirport() async {
        guard airport == nil, let id = profile.homeAirportID, let database = referenceData.database else { return }
        airport = try? await database.airport(id: id)
    }

    private func save() {
        isSaving = true
        error = nil
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let updated = Profile(
            id: profile.id, username: normalizedUsername, displayName: name.isEmpty ? nil : name,
            homeAirportID: homeAirportID
        )
        Task {
            defer { isSaving = false }
            do {
                try await account.save(updated)
                if !isFirstSetup { dismiss() }
            } catch {
                self.error = error.accountMessage
            }
        }
    }
}
