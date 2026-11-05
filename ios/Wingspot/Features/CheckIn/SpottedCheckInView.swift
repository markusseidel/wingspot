import Account
import Persistence
import ReferenceData
import SwiftData
import SwiftUI
import WingspotCore

/// The Spotted check-in (concept §4.1). Works fully offline: everything is saved on the device first.
struct SpottedCheckInView: View {
    let onDone: () -> Void

    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.modelContext) private var modelContext
    @Environment(AccountStore.self) private var account
    @Environment(CheckInSyncCoordinator.self) private var sync: CheckInSyncCoordinator?

    @State private var input = ""
    @State private var type: AircraftType?
    @State private var airport: Airport?
    @State private var airportWasChosen = false
    @State private var position: GeoCoordinate?
    @State private var result: SpottedResult?
    @State private var saveFailed = false
    @FocusState private var isFocused: Bool

    private var registration: Registration? { Registration(input) }
    private var hasInput: Bool { !input.trimmingCharacters(in: .whitespaces).isEmpty }
    private var canSave: Bool { hasInput ? registration != nil : type != nil }

    var body: some View {
        Group {
            if let result {
                CheckInResultView(result: result, onAnother: reset, onDone: onDone)
            } else {
                form
            }
        }
        .navigationTitle("Spotted")
        .navigationBarBackButtonHidden(result != nil)
        .task { position = await LocationProvider.currentPosition() }
        .task(id: NearestKey(position: position, dataVersion: referenceData.database?.dataVersion)) {
            await suggestAirport()
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
                TextField("Registration, e.g. DAIMA", text: $input)
                    .font(.system(.title2, design: .monospaced))
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($isFocused)
            } footer: {
                status
            }

            Section {
                NavigationLink {
                    TypeSearchView(selection: $type)
                } label: {
                    LabeledContent("Aircraft type", value: type?.name ?? String(localized: "Optional"))
                }
                NavigationLink {
                    AirportSearchView(selection: Binding(
                        get: { airport },
                        set: { airport = $0; airportWasChosen = true }
                    ))
                } label: {
                    LabeledContent("Airport", value: airport.map { "\($0.code) · \($0.name)" } ?? String(localized: "None"))
                }
            } footer: {
                if referenceData.database == nil {
                    if referenceData.isUpdating {
                        Text("Downloading aircraft and airport data.")
                    } else {
                        Text("Aircraft and airport search needs one download while online. You can still check in by registration.")
                    }
                }
            }

            Section {
                Button("Check in", action: save)
                    .disabled(!canSave)
            }
        }
        .onAppear { isFocused = true }
    }

    @ViewBuilder private var status: some View {
        if let registration {
            Label {
                Text(registration.value).font(.system(.body, design: .monospaced).bold())
                    + Text(verbatim: "  ·  \(Self.countryName(registration.countryCode))")
            } icon: {
                Text(Self.flag(registration.countryCode))
            }
            .accessibilityLabel("\(registration.value), registered in \(Self.countryName(registration.countryCode))")
        } else if hasInput {
            Text("Not a valid registration yet")
        } else {
            Text("Enter a registration, or choose a type if you couldn't read it.")
        }
    }

    private func save() {
        let draft = SpottedDraft(
            registration: registration,
            type: type.map { .init(icaoCode: $0.icaoCode, name: $0.name) },
            place: airport.map { .init(airportID: $0.id, code: $0.code) },
            position: position
        )
        do {
            result = try CheckInStore(context: modelContext).saveSpotted(draft, ownerID: account.userID)
            // Saved on the device first. This sends it when signed in and online, and otherwise it waits.
            sync?.requestSync()
        } catch {
            saveFailed = true
        }
    }

    /// Starts the next check-in and keeps the airport, because spotters log several planes in one place.
    private func reset() {
        input = ""
        type = nil
        result = nil
    }

    private func suggestAirport() async {
        guard !airportWasChosen, let position, let database = referenceData.database else { return }
        airport = try? await database.nearestAirport(to: position)
    }

    private struct NearestKey: Hashable {
        let position: GeoCoordinate?
        let dataVersion: String?
    }

    private static func countryName(_ code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }

    private static func flag(_ code: String) -> String {
        code.unicodeScalars
            .compactMap { Unicode.Scalar(127_397 + $0.value) }
            .map(String.init)
            .joined()
    }
}

#Preview {
    NavigationStack { SpottedCheckInView(onDone: {}) }
        .environment(ReferenceDataStore(database: nil))
        .modelContainer(for: LocalCheckIn.self, inMemory: true)
}
