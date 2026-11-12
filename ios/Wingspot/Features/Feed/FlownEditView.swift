import Persistence
import ReferenceData
import SwiftData
import SwiftUI
import WingspotCore

/// Where to look a flight or an aircraft up on Flightradar24. Wingspot sends nothing there: the link only opens the page.
enum Flightradar24 {
    /// The page of a flight number such as `LH400`, which lists the aircraft that flew it.
    static func flight(_ flightNumber: String) -> URL? {
        let code = flightNumber.filter { $0.isLetter || $0.isNumber }.lowercased()
        return code.isEmpty ? nil : URL(string: "https://www.flightradar24.com/data/flights/\(code)")
    }

    /// The page of a registration such as `D-AIMA`, with its type and history.
    static func aircraft(_ registration: Registration) -> URL? {
        URL(string: "https://www.flightradar24.com/data/aircraft/\(registration.value.lowercased())")
    }
}

/// Fills in what was left out when a flight was checked in: the registration, the aircraft type and the other details.
struct FlownEditView: View {
    let flightID: UUID
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(CheckInSyncCoordinator.self) private var sync: CheckInSyncCoordinator?

    @State private var route = ""
    @State private var flightNumber = ""
    @State private var registrationInput = ""
    @State private var typeCode: String?
    @State private var typeName: String?
    @State private var cabin: CabinClass?
    @State private var seat = ""
    @State private var loaded = false
    @State private var failed = false

    private var registration: Registration? { Registration(registrationInput) }
    private var hasRegistrationInput: Bool { !registrationInput.trimmingCharacters(in: .whitespaces).isEmpty }
    private var typeBinding: Binding<AircraftType?> {
        Binding(
            get: { typeCode.map { AircraftType(icaoCode: $0, manufacturer: typeName ?? $0, model: "") } },
            set: { typeCode = $0?.icaoCode; typeName = $0?.name }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Flight", value: route)
                }
                Section {
                    TextField("Flight number, e.g. LH400", text: $flightNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
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
                    Picker("Cabin", selection: $cabin) {
                        Text("Not set").tag(CabinClass?.none)
                        ForEach(CabinClass.allCases, id: \.self) { Text($0.title).tag(CabinClass?.some($0)) }
                    }
                    TextField("Seat, e.g. 34K", text: $seat)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } header: {
                    Text("Details")
                } footer: {
                    if hasRegistrationInput, registration == nil {
                        Text("Not a valid registration yet")
                    }
                }
                lookup
            }
            .navigationTitle("Edit flight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!loaded || (hasRegistrationInput && registration == nil))
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

    /// Links to look up the aircraft, for a flight number or registration that is filled in.
    @ViewBuilder private var lookup: some View {
        let flightPage = Flightradar24.flight(flightNumber)
        let aircraftPage = registration.flatMap(Flightradar24.aircraft)
        if flightPage != nil || aircraftPage != nil {
            Section {
                if let flightPage {
                    Link(destination: flightPage) { Label("Look up the flight on Flightradar24", systemImage: "arrow.up.right.square") }
                }
                if let aircraftPage {
                    Link(destination: aircraftPage) { Label("Look up the aircraft on Flightradar24", systemImage: "arrow.up.right.square") }
                }
            } footer: {
                Text("Opens Flightradar24 in your browser. Nothing from Wingspot is sent there.")
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        let id = flightID
        let flights = (try? modelContext.fetch(FetchDescriptor<LocalCheckIn>(predicate: #Predicate { $0.id == id }))) ?? []
        guard let flight = flights.first else { return }
        route = "\(flight.originCode ?? "?") → \(flight.destinationCode ?? "?")"
        flightNumber = flight.flightNumber ?? ""
        registrationInput = flight.registration ?? ""
        typeCode = flight.typeICAO
        typeName = flight.typeName
        cabin = flight.cabin.flatMap(CabinClass.init(rawValue:))
        seat = flight.seat ?? ""
        loaded = true
    }

    private func save() {
        do {
            try CheckInStore(context: modelContext).updateFlown(
                id: flightID, registration: registration, type: typeCode.map { .init(icaoCode: $0, name: typeName ?? $0) },
                flightNumber: flightNumber, cabin: cabin, seat: seat
            )
            sync?.requestSync()
            onSaved()
            dismiss()
        } catch {
            failed = true
        }
    }
}
