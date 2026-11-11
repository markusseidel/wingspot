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
struct FlownCheckInView: View {
    let onDone: () -> Void

    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.modelContext) private var modelContext
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
    @State private var result: FlownResult?
    @State private var saveFailed = false
    @State private var tripPhoto: PreparedPhoto?
    @State private var isPreparingPhoto = false
    @State private var showCamera = false
    @State private var photo: PhotosPickerItem?
    @State private var isReadingImage = false
    @State private var scanProblem: ScanProblem?
    @State private var legChoices: [BoardingPass.Leg] = []

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
                FlownResultView(result: result, onAnother: reset, onDone: onDone)
            } else {
                form
            }
        }
        .navigationTitle("Flown")
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
            } footer: {
                Text("Fills in the route, date, flight number and seat. Your name and booking code are never read or saved.")
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
                    TypeSearchView(selection: $type)
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
            }

            PhotoSection(photo: $tripPhoto, isPreparing: $isPreparingPhoto)

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
            photo: tripPhoto
        )
        do {
            result = try CheckInStore(context: modelContext).saveFlown(draft, ownerID: account.userID, at: Self.moment(of: date))
            sync?.requestSync()
        } catch {
            saveFailed = true
        }
    }

    /// A flight has a day but no time here. Today keeps the real time. Any other day uses midday, which stays
    /// on that day in every time zone near the user.
    private static func moment(of day: Date) -> Date {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return Date() }
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
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
        tripPhoto = nil
        result = nil
    }
}

private struct FlownResultView: View {
    let result: FlownResult
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
            }
            Spacer()
            VStack(spacing: 12) {
                Button(action: onAnother) {
                    Text("Check in another").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
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
