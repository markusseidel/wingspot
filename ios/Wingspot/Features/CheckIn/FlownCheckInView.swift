import Account
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
    @State private var flightNumber = ""
    @State private var registrationInput = ""
    @State private var type: AircraftType?
    @State private var cabin: CabinClass?
    @State private var seat = ""
    @State private var result: FlownResult?
    @State private var saveFailed = false

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
        .alert("Couldn't save this check-in", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try again.")
        }
    }

    private var form: some View {
        Form {
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

            Section {
                Button("Check in", action: save)
                    .disabled(!canSave)
            } footer: {
                if hasRegistrationInput, registration == nil {
                    Text("Not a valid registration yet")
                }
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
            type: type.map { .init(icaoCode: $0.icaoCode, name: $0.name) }, cabin: cabin, seat: seat
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
                    Text("\(km) km")
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
