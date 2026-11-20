import Account
import PhotosUI
import ReferenceData
import SwiftUI

/// Sets the username, name and home airport, right after the first sign-in and later from the profile.
struct ProfileEditorView: View {
    let profile: Profile
    let isFirstSetup: Bool

    @Environment(AccountStore.self) private var account
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.dismiss) private var dismiss
    @Environment(AvatarStore.self) private var avatars

    @State private var username: String
    @State private var displayName: String
    @State private var airport: Airport?
    @State private var homeAirportID: Int?
    @State private var isSaving = false
    @State private var error: LocalizedStringResource?
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var currentPhoto: UIImage?
    @State private var isChangingPhoto = false
    @State private var photoFailed = false

    init(profile: Profile, isFirstSetup: Bool) {
        self.profile = profile
        self.isFirstSetup = isFirstSetup
        // A generated username is no use as a starting point.
        _username = State(initialValue: profile.hasChosenUsername ? profile.username : "")
        _displayName = State(initialValue: profile.displayName ?? "")
        _homeAirportID = State(initialValue: profile.homeAirportID)
    }

    private var normalizedUsername: String { Username.normalized(username) }

    private var photoSection: some View {
        Section {
            HStack(spacing: 16) {
                AvatarView(id: profile.id, name: displayName.isEmpty ? username : displayName, size: 72)
                VStack(alignment: .leading, spacing: 10) {
                    PhotosPicker(selection: $pickedPhoto, matching: .images) {
                        Text(currentPhoto == nil ? "Choose photo" : "Change photo")
                    }
                    if currentPhoto != nil {
                        Button("Remove photo", role: .destructive) { Task { await changePhoto(nil) } }
                    }
                }
                .disabled(isChangingPhoto)
                if isChangingPhoto { ProgressView() }
            }
        } header: {
            Text("Profile photo")
        } footer: {
            if photoFailed {
                Text("Couldn't save the photo. Try again.").foregroundStyle(.red)
            } else {
                Text("Shown next to your name wherever people see you. A square from the middle of the picture is used.")
            }
        }
        .task { currentPhoto = await avatars.image(for: profile.id) }
        .onChange(of: pickedPhoto) {
            guard let item = pickedPhoto else { return }
            pickedPhoto = nil
            Task { await changePhoto(item) }
        }
    }

    /// Sets the picked picture as the profile image, or removes the image when there is none.
    private func changePhoto(_ item: PhotosPickerItem?) async {
        isChangingPhoto = true
        photoFailed = false
        defer { isChangingPhoto = false }
        do {
            if let item {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let prepared = await Task.detached(operation: { AvatarStore.prepare(data) }).value else {
                    photoFailed = true
                    return
                }
                try await avatars.setMine(profile.id, jpeg: prepared.jpeg, preview: prepared.preview)
                currentPhoto = prepared.preview
            } else {
                try await avatars.setMine(profile.id, jpeg: nil, preview: nil)
                currentPhoto = nil
            }
        } catch {
            photoFailed = true
        }
    }

    var body: some View {
        Form {
            photoSection
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
        .task {
            // Apple gives the name only at the first sign-in, so offer it once.
            if isFirstSetup, displayName.isEmpty, let name = account.takeSuggestedName() { displayName = name }
        }
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
