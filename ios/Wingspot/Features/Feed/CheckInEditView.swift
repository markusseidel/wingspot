import Account
import Persistence
import ReferenceData
import SwiftData
import SwiftUI
import WingspotCore

/// Corrects a sighting (the aircraft) or an airport visit (the reason), adds a photo, and says who can see it. Flights have their
/// own, longer screen.
struct CheckInEditView: View {
    let checkInID: UUID
    /// The friends tagged on the visit now.
    let tags: [PersonTag]
    /// The photos the check-in already has on the server, each of which can be deleted here.
    var existingPhotos: [FeedPhoto] = []
    var onDeletePhoto: ((FeedPhoto) async -> Bool)?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(CheckInSyncCoordinator.self) private var sync: CheckInSyncCoordinator?

    @State private var kind = ""
    @State private var title = ""
    @State private var registrationInput = ""
    @State private var typeCode: String?
    @State private var typeName: String?
    @State private var reason = VisitContext.spotting
    @State private var loaded = false
    @State private var failed = false
    @State private var photos: [PreparedPhoto] = []
    @State private var isPreparingPhoto = false
    /// How many more photos the check-in can take.
    @State private var roomForPhotos = 0
    @State private var tagged: [PersonTag] = []
    /// Existing photos marked as removed. They are deleted when the screen is saved.
    @State private var removedPhotos: Set<UUID> = []
    @State private var isSaving = false
    /// A sighting's spotting place, and whether the places of its airport were read (so "None" is a real choice).
    @State private var spot: SpotLocation?
    @State private var originalSpotID: Int?
    @State private var spotsLoaded = false
    @State private var airportID: Int?
    @State private var inSession = false
    /// When it happened. Not shown for the visit of a flight: it follows the flight.
    @State private var when = WhenChoice.now
    @State private var originalWhen = WhenChoice.now
    @State private var followsFlight = false

    private var registration: Registration? { Registration(registrationInput) }
    private var hasRegistrationInput: Bool { !registrationInput.trimmingCharacters(in: .whitespaces).isEmpty }
    private var typeBinding: Binding<AircraftType?> {
        Binding(
            get: { typeCode.map { AircraftType(icaoCode: $0, manufacturer: typeName ?? $0, model: "") } },
            set: { typeCode = $0?.icaoCode; typeName = $0?.name }
        )
    }
    /// A sighting needs a registration or a type, like a new one.
    private var canSave: Bool {
        guard loaded, !isPreparingPhoto else { return false }
        if kind == "spotted" { return (registration != nil && hasRegistrationInput) || typeCode != nil }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(kind == "airport" ? "Airport" : "Aircraft", value: title)
                }
                if kind == "spotted" {
                    Section {
                        TextField("Registration, e.g. DAIMA", text: $registrationInput)
                            .font(.system(.body, design: .monospaced))
                            .keyboardType(.asciiCapable)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        NavigationLink {
                            TypeSearchView(selection: typeBinding)
                        } label: {
                            LabeledContent("Aircraft type", value: typeName ?? String(localized: "Optional"))
                        }
                        SightingSpotRow(airportID: airportID, inSession: inSession, choice: $spot, loaded: $spotsLoaded)
                    } header: {
                        Text("Details")
                    } footer: {
                        if hasRegistrationInput, registration == nil {
                            Text("Not a valid registration yet")
                        }
                    }
                } else if kind == "airport" {
                    Section {
                        Picker("Reason", selection: $reason) {
                            ForEach(VisitContext.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        WithFriendsRow(selection: $tagged)
                    }
                }
                if !followsFlight { WhenSection(choice: $when, photos: photos) }
                if roomForPhotos > 0 || !existingPhotos.isEmpty {
                    PhotoSection(photos: $photos, isPreparing: $isPreparingPhoto, limit: roomForPhotos, existing: existingPhotos, removedExisting: $removedPhotos, removable: onDeletePhoto != nil)
                }
                Section { CheckInVisibilityPicker(checkInID: checkInID) }
            }
            .navigationTitle(kind == "airport" ? "Edit visit" : "Edit sighting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(!canSave || isSaving)
                }
            }
            .alert("Couldn't save this check-in", isPresented: $failed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please try again.")
            }
            .task { load() }
        }
    }

    private func load() {
        guard !loaded else { return }
        let id = checkInID
        let matches = (try? modelContext.fetch(FetchDescriptor<LocalCheckIn>(predicate: #Predicate { $0.id == id }))) ?? []
        guard let checkIn = matches.first else { return }
        kind = checkIn.kind
        followsFlight = checkIn.flightID != nil
        originalWhen = .existing(checkIn.occurredAt, timeKnown: checkIn.timeKnown != false)
        when = originalWhen
        switch checkIn.kind {
        case "spotted":
            title = checkIn.registration ?? checkIn.typeICAO ?? "?"
            registrationInput = checkIn.registration ?? ""
            typeCode = checkIn.typeICAO
            typeName = checkIn.typeName
            airportID = checkIn.airportID
            inSession = checkIn.visitID != nil
            originalSpotID = checkIn.spotID
            spot = checkIn.spotID.map { SpotLocation(id: $0, name: checkIn.spotName ?? "", latitude: 0, longitude: 0, description: nil, status: "approved", mine: false, sessions: 0) }
        case "airport":
            title = checkIn.airportCode ?? "?"
            reason = checkIn.visitContext.flatMap(VisitContext.init(rawValue:)) ?? .spotting
        default:
            break
        }
        // The server's photos count too: a check-in restored on a new phone has none of its own copies here.
        roomForPhotos = max(0, CheckInStore.maxPhotos - max((try? CheckInStore(context: modelContext).photoCount(for: id)) ?? 0, existingPhotos.count))
        tagged = tags
        loaded = true
    }

    /// Deletes the photos that were marked as removed, then saves the details. If a photo can't be deleted nothing else is saved and
    /// the screen stays open, so the person can try again or cancel.
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        for photo in existingPhotos where removedPhotos.contains(photo.id) {
            if await onDeletePhoto?(photo) != true {
                failed = true
                return
            }
            removedPhotos.remove(photo.id)
        }
        saveDetails()
    }

    /// What the edit does with the place: nothing when the picker was not shown, otherwise what was chosen.
    private var spotChange: SpotChange {
        guard spotsLoaded, !inSession else { return .keep }
        if let spot { return spot.id == originalSpotID ? .keep : .set(id: spot.id, name: spot.name) }
        return originalSpotID == nil ? .keep : .clear
    }

    /// The new date and time when the "When" row was changed, nothing when it was left alone.
    private var newMoment: (date: Date, timeKnown: Bool)? {
        guard !followsFlight, when != originalWhen else { return nil }
        return when.moment()
    }

    private func saveDetails() {
        do {
            let store = CheckInStore(context: modelContext)
            let moment = newMoment
            if kind == "spotted" {
                try store.updateSpotted(
                    id: checkInID, registration: registration,
                    type: typeCode.map { .init(icaoCode: $0, name: typeName ?? $0) },
                    spot: spotChange, occurredAt: moment?.date, timeKnown: moment?.timeKnown
                )
            } else if kind == "airport" {
                try store.updateVisit(
                    id: checkInID, reason: reason, tagged: tagged.map(\.id) == tags.map(\.id) ? nil : tagged.map(\.id),
                    occurredAt: moment?.date, timeKnown: moment?.timeKnown
                )
            }
            if !photos.isEmpty { try store.addPhotos(photos, to: checkInID) }
            sync?.requestSync()
            onSaved()
            dismiss()
        } catch {
            failed = true
        }
    }
}
