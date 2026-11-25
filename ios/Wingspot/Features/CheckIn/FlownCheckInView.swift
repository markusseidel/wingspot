import Account
import BCBP
import PhotosUI
import Persistence
import ReferenceData
import SwiftData
import SwiftUI
import WingspotCore

extension CabinClass {
    var title: LocalizedStringResource {
        switch self {
        case .economy: "Economy"
        case .premiumEconomy: "Premium Economy"
        case .business: "Business"
        case .first: "First"
        }
    }
}

/// The Flown check-in (concept §4.2). Saves on the device first and works offline once the airport data is downloaded.
/// The first values of the flight form for a return flight: the route the other way round, the same day, and the
/// cabin and friends of the flight before. The flight number, aircraft and seat differ, so they stay empty.
struct ReturnStart: Identifiable {
    let id = UUID()
    let origin: Airport
    let destination: Airport
    let date: Date
    let cabin: CabinClass?
    let tagged: [PersonTag]
}

struct FlownCheckInView: View {
    let onDone: () -> Void

    init(start: ReturnStart? = nil, onDone: @escaping () -> Void) {
        self.onDone = onDone
        _origin = State(initialValue: start?.origin)
        _destination = State(initialValue: start?.destination)
        _date = State(initialValue: start?.date ?? Date())
        _cabin = State(initialValue: start?.cabin)
        _tagged = State(initialValue: start?.tagged ?? [])
    }

    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.modelContext) private var modelContext

    /// The types of your earlier flights with this flight number.
    private var recentTypes: [AircraftType] {
        let found = (try? CheckInStore(context: modelContext).recentTypes(forFlight: flightNumber, userID: account.userID)) ?? []
        return found.map { AircraftType(icaoCode: $0.icaoCode, manufacturer: $0.name, model: "") }
    }
    @Environment(AccountStore.self) private var account
    @Environment(CheckInSyncCoordinator.self) private var sync: CheckInSyncCoordinator?

    @State private var origin: Airport?
    @State private var destination: Airport?
    @State private var date = Date()
    /// The year the app guessed for a scanned boarding pass, which has a day but no year.
    @State private var assumedYear: Int?
    @State private var flightNumber = ""
    @State private var registrationInput = ""
    @State private var type: AircraftType?
    @State private var cabin: CabinClass?
    @State private var seat = ""
    @State private var tagged: [PersonTag] = []
    @State private var result: FlownResult?
    @State private var saveFailed = false
    @State private var tripPhotos: [PreparedPhoto] = []
    @State private var isPreparingPhoto = false
    @State private var showCamera = false
    @State private var photo: PhotosPickerItem?
    @State private var isReadingImage = false
    @State private var scanProblem: ScanProblem?
    @State private var legChoices: [BoardingPass.Leg] = []
    @State private var showFileImporter = false
    @State private var isImportingFile = false
    @State private var importProblem: KmlImportProblem?
    /// False when the server switched the KML import off. On until the server says otherwise.
    @AppStorage(KmlSwitches.importKey) private var kmlImportOn = true
    /// A KML file shared into the app, read as soon as the form is there.
    @State private var kmlInbox = KmlInbox.shared
    /// Several KML files picked or shared at once: read in one list (#236).
    @State private var batchURLs: [URL] = []
    @State private var importNotice: ImportNotice?
    /// The positions of an imported flight. They are kept on this iPhone only and never uploaded.
    @State private var importedTrack: [GeoCoordinate] = []

    private enum ScanProblem: Identifiable {
        case noBoardingPass, needsData
        /// The codes on the pass that aren't airports in the data, such as a railway station on a train ticket.
        case airportsUnknown(String)

        var id: String {
            switch self {
            case .noBoardingPass: "noBoardingPass"
            case .needsData: "needsData"
            case .airportsUnknown: "airportsUnknown"
            }
        }
    }

    private var registration: Registration? { Registration(registrationInput) }
    private var hasRegistrationInput: Bool { !registrationInput.trimmingCharacters(in: .whitespaces).isEmpty }
    private var hasRoute: Bool { origin != nil && destination != nil && origin?.id != destination?.id }
    private var canSave: Bool { hasRoute && (!hasRegistrationInput || registration != nil) }

    var body: some View {
        Group {
            if let result {
                FlownResultView(result: result, trackNote: savedTrackNote, onReturn: startReturn, onAnother: reset, onDone: onDone)
            } else {
                form
            }
        }
        .navigationTitle("Flown")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(result != nil)
        .fullScreenCover(isPresented: $showCamera) {
            BoardingPassCameraView { pass in handle(pass) }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { await readImage(item) }
        }
        .confirmationDialog("Which flight?", isPresented: Binding(
            get: { !legChoices.isEmpty }, set: { if !$0 { legChoices = [] } }
        ), titleVisibility: .visible) {
            ForEach(Array(legChoices.enumerated()), id: \.offset) { _, leg in
                Button("\(leg.from) → \(leg.to) · \(leg.carrier)\(leg.flightNumber)") { apply(leg) }
            }
        }
        .task(id: kmlInbox.pending) {
            guard !kmlInbox.pending.isEmpty else { return }
            // Several files shared at once arrive one after the other: wait a moment, then take them all.
            try? await Task.sleep(for: .milliseconds(800))
            openFiles(kmlInbox.takeAll())
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.data], allowsMultipleSelection: true) { picked in
            guard case .success(let urls) = picked else { return }
            openFiles(urls)
        }
        .sheet(isPresented: Binding(get: { !batchURLs.isEmpty }, set: { if !$0 { batchURLs = [] } })) {
            NavigationStack { KmlBatchView(urls: batchURLs, onDone: { batchURLs = []; onDone() }) }
        }
        .alert(importProblem.map { String(localized: $0.title) } ?? "", isPresented: Binding(
            get: { importProblem != nil }, set: { if !$0 { importProblem = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importProblem.map { String(localized: $0.message) } ?? "")
        }
        .alert(scanProblemTitle, isPresented: Binding(
            get: { scanProblem != nil }, set: { if !$0 { scanProblem = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(scanProblemMessage)
        }
        .alert("Couldn't save this check-in", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try again.")
        }
    }

    private var form: some View {
        Form {
            Section {
                if BoardingPassScanning.cameraIsAvailable {
                    Button("Scan boarding pass", systemImage: "barcode.viewfinder") { showCamera = true }
                }
                // The label closure can't read state from the view, so the text is chosen before it.
                let pickerTitle: LocalizedStringResource = isReadingImage ? "Reading…" : "Read from a picture"
                PhotosPicker(selection: $photo, matching: .images) {
                    Label { Text(pickerTitle) } icon: { Image(systemName: "photo") }
                }
                .disabled(isReadingImage)
                if kmlImportOn {
                    let importTitle: LocalizedStringResource = isImportingFile ? "Reading…" : "Import a KML file"
                    Button { showFileImporter = true } label: {
                        Label { Text(importTitle) } icon: { Image(systemName: "doc.badge.arrow.up") }
                    }
                    .disabled(isImportingFile)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Fills in the route, date, flight number and seat. Your name and booking code are never read or saved.")
                    if kmlImportOn {
                        Text("A KML file of a flight is read on this iPhone. The file and its route are never uploaded.")
                    }
                }
            }

            if let importNotice {
                Section {
                    if !importNotice.found.isEmpty {
                        Text("Filled in from the file: \(ImportNotice.list(importNotice.found)).")
                    }
                    if !importNotice.missing.isEmpty {
                        Text("Not found in the file: \(ImportNotice.list(importNotice.missing)). Please add them by hand.")
                    }
                    if let trackSummary { Text(trackSummary) }
                    if let estimateNote { Text(estimateNote).foregroundStyle(.orange) }
                    if hasDuplicate {
                        Label("You already have a flight \(normalizedFlightNumber) on this day. Save it only if it is another flight.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Imported flight")
                } footer: {
                    Text("Please check everything before you save.")
                }
            }

            Section {
                NavigationLink {
                    AirportSearchView(selection: $origin)
                } label: {
                    LabeledContent("From", value: origin.map { "\($0.code) · \($0.name)" } ?? String(localized: "Choose"))
                }
                NavigationLink {
                    AirportSearchView(selection: $destination)
                } label: {
                    LabeledContent("To", value: destination.map { "\($0.code) · \($0.name)" } ?? String(localized: "Choose"))
                }
                DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
            } footer: {
                if referenceData.database == nil {
                    if referenceData.isUpdating {
                        Text("Downloading aircraft and airport data.")
                    } else {
                        Text("Choosing airports needs one download while online.")
                    }
                } else if origin != nil, origin?.id == destination?.id {
                    Text("Choose two different airports.")
                } else if let assumedYear, Calendar.current.component(.year, from: date) == assumedYear {
                    Text("A boarding pass has the day but not the year, so Wingspot used \(String(assumedYear)). If the flight was in an earlier year, change the date.")
                }
            }

            Section("Flight") {
                TextField("Flight number, e.g. LH400", text: $flightNumber)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                TextField("Registration, e.g. DAIMA", text: $registrationInput)
                    .font(.system(.body, design: .monospaced))
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                NavigationLink {
                    TypeSearchView(selection: $type, recent: recentTypes)
                } label: {
                    LabeledContent("Aircraft type", value: type?.name ?? String(localized: "Optional"))
                }
                Picker("Cabin", selection: $cabin) {
                    Text("Not set").tag(CabinClass?.none)
                    ForEach(CabinClass.allCases, id: \.self) { Text($0.title).tag(CabinClass?.some($0)) }
                }
                TextField("Seat, e.g. 34K", text: $seat)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                WithFriendsRow(selection: $tagged)
            }

            PhotoSection(photos: $tripPhotos, isPreparing: $isPreparingPhoto)

            Section {
                Button("Check in", action: save)
                    .disabled(!canSave || isPreparingPhoto)
            } footer: {
                if hasRegistrationInput, registration == nil {
                    Text("Not a valid registration yet")
                }
            }
        }
    }

    private var scanProblemTitle: LocalizedStringKey {
        switch scanProblem {
        case .noBoardingPass: "No boarding pass found"
        case .airportsUnknown: "Airports not found"
        case .needsData: "Airport data is missing"
        case nil: "OK"
        }
    }

    private var scanProblemMessage: LocalizedStringKey {
        switch scanProblem {
        case .noBoardingPass: "Try a clearer picture, or enter the flight by hand."
        case .airportsUnknown(let codes):
            "Not an airport in the app's data: \(codes). A train ticket, such as Lufthansa Express Rail, is not a flight and can't be logged. Otherwise, enter the flight by hand."
        case .needsData: "Reading a boarding pass needs one download while online."
        case nil: "OK"
        }
    }

    private var normalizedFlightNumber: String { flightNumber.filter { !$0.isWhitespace }.uppercased() }

    /// Another flight of yours with the same flight number on the same day, saved on this iPhone.
    private var hasDuplicate: Bool {
        guard !normalizedFlightNumber.isEmpty else { return false }
        let owner = account.userID
        let found = (try? modelContext.fetch(FetchDescriptor<LocalCheckIn>(predicate: #Predicate {
            $0.kind == "flown" && $0.flightNumber != nil && $0.ownerID == owner
        }))) ?? []
        return found.contains { $0.flightNumber == normalizedFlightNumber && Calendar.current.isDate($0.occurredAt, inSameDayAs: date) }
    }

    /// Says so when the route has a big gap: its flown distance is then an estimate (#239).
    private var estimateNote: String? {
        guard importedTrack.count >= 2, FlightTrack.isEstimated(importedTrack) else { return nil }
        let gap = DistanceUnit.preferred.format(km: Int(FlightTrack.largestGapKm(importedTrack).rounded()))
        return String(localized: "The route has a gap of \(gap). The flown distance is an estimate, a little too short.")
    }

    private var trackSummary: String? {
        guard importedTrack.count >= 2, let detour = KmlImport.detour(track: importedTrack, origin: origin, destination: destination) else { return nil }
        let flown = DistanceUnit.preferred.format(km: detour.flownKm)
        if detour.extraKm > 0 {
            return String(localized: "Route found: \(importedTrack.count) positions, \(flown) flown, \(DistanceUnit.preferred.format(km: detour.extraKm)) (\(String(detour.percent) + " %")) more than the direct way. The route stays on this iPhone.")
        }
        return String(localized: "Route found: \(importedTrack.count) positions, \(flown) flown. The route stays on this iPhone.")
    }

    /// What the result page says about the route that was saved with the flight.
    private var savedTrackNote: LocalizedStringResource? {
        importedTrack.count >= 2 ? "The flown route (\(importedTrack.count) positions) is saved on this iPhone." : nil
    }

    /// One file fills this form; several open the list that adds them all (#236).
    private func openFiles(_ urls: [URL]) {
        if urls.count == 1, let url = urls.first {
            Task { await importFile(url) }
        } else if urls.count > 1 {
            batchURLs = urls
        }
    }

    /// Fills the form from a KML file. A field the file doesn't have stays as it is, and the notice says which.
    private func importFile(_ url: URL) async {
        isImportingFile = true
        defer { isImportingFile = false }
        switch await KmlImport.read(url) {
        case .failure(let problem):
            importProblem = problem
        case .success(let flight):
            await apply(flight)
        }
    }

    private func apply(_ flight: KmlFlight) async {
        var found: [ImportedField] = []
        if let database = referenceData.database {
            var from: Airport?, to: Airport?
            if let code = flight.origin?.iata { from = try? await database.airport(iata: code) }
            if let code = flight.destination?.iata { to = try? await database.airport(iata: code) }
            if let from, let to, from.id != to.id {
                origin = from
                destination = to
                found.append(.route)
            }
            if let code = flight.aircraftTypeCode, let known = try? await database.aircraftType(icao: code) {
                type = known
                found.append(.aircraftType)
            }
        }
        if let day = flight.departureDay() {
            date = day
            assumedYear = nil
            found.append(.date)
        }
        if let number = flight.flightNumber {
            flightNumber = number
            found.append(.flightNumber)
        }
        if let registration = flight.registration, Registration(registration) != nil {
            registrationInput = registration
            found.append(.registration)
        }
        importedTrack = flight.track.count >= 2 ? flight.track : []
        importNotice = ImportNotice(found: found, missing: ImportedField.allCases.filter { !found.contains($0) })
    }

    private func readImage(_ item: PhotosPickerItem) async {
        isReadingImage = true
        defer { isReadingImage = false; photo = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let pass = await BoardingPassScanning.boardingPass(inImageData: data)
        else {
            scanProblem = .noBoardingPass
            return
        }
        handle(pass)
    }

    private func handle(_ pass: BoardingPass) {
        if pass.legs.count == 1, let leg = pass.legs.first {
            apply(leg)
        } else {
            legChoices = pass.legs
        }
    }

    /// Fills the form from one flight on the pass. The cabin stays as it is, because the booking class letter
    /// means different things at different airlines.
    private func apply(_ leg: BoardingPass.Leg) {
        guard let database = referenceData.database else {
            scanProblem = .needsData
            return
        }
        Task {
            let from = try? await database.airport(iata: leg.from)
            let to = try? await database.airport(iata: leg.to)
            guard let from, let to else {
                let missing = [from == nil ? leg.from : nil, to == nil ? leg.to : nil].compactMap { $0 }
                scanProblem = .airportsUnknown(missing.joined(separator: ", "))
                return
            }
            origin = from
            destination = to
            flightNumber = leg.carrier + leg.flightNumber
            seat = leg.seat ?? ""
            if let flightDate = leg.flightDate(near: Date()) {
                date = min(flightDate, Date())
                assumedYear = Calendar.current.component(.year, from: date)
            }
        }
    }

    private func save() {
        guard let origin, let destination else { return }
        let distance = GreatCircle.distanceKm(from: origin.coordinate, to: destination.coordinate)
        let draft = FlownDraft(
            origin: .init(airportID: origin.id, code: origin.code),
            destination: .init(airportID: destination.id, code: destination.code),
            distanceKm: Int(distance.rounded()), flightNumber: flightNumber, registration: registration,
            type: type.map { .init(icaoCode: $0.icaoCode, name: $0.name) }, cabin: cabin, seat: seat,
            photos: tripPhotos, tagged: tagged.map(\.id)
        )
        do {
            let saved = try CheckInStore(context: modelContext).saveFlown(draft, ownerID: account.userID, at: FlightDay.moment(of: date))
            if importedTrack.count >= 2 { try? FlightTrackFiles.standard.save(importedTrack, for: saved.id) }
            result = saved
            sync?.requestSync()
        } catch {
            saveFailed = true
        }
    }

    /// Starts the flight back: the route the other way round, with the same day, cabin and friends.
    private func startReturn() {
        guard let from = origin, let to = destination else { return }
        origin = to
        destination = from
        flightNumber = ""
        registrationInput = ""
        type = nil
        seat = ""
        tripPhotos = []
        assumedYear = nil
        clearImport()
        result = nil
    }

    /// Starts the next flight and keeps the date.
    private func reset() {
        origin = nil
        destination = nil
        flightNumber = ""
        registrationInput = ""
        type = nil
        cabin = nil
        seat = ""
        tagged = []
        tripPhotos = []
        clearImport()
        result = nil
    }

    private func clearImport() {
        importedTrack = []
        importNotice = nil
    }
}

private struct FlownResultView: View {
    let result: FlownResult
    let trackNote: LocalizedStringResource?
    let onReturn: () -> Void
    let onAnother: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: result.timesOnRoute == 1 ? "sparkles" : "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(result.route)
                    .font(.system(.largeTitle, design: .monospaced).bold())
                Text(headline)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                if let km = result.distanceKm {
                    Text(verbatim: DistanceUnit.preferred.format(km: km))
                        .foregroundStyle(.secondary)
                }
                if let trackNote {
                    Text(trackNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            Spacer()
            VStack(spacing: 12) {
                Button(action: onReturn) {
                    Label("Return flight", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button(action: onAnother) {
                    Text("Check in another").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button(action: onDone) {
                    Text("Done").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
        .padding()
        .sensoryFeedback(.success, trigger: result.id)
    }

    private var headline: LocalizedStringResource {
        result.timesOnRoute == 1 ? "First flight on this route!" : "Flight number \(result.timesOnRoute) on this route"
    }
}
