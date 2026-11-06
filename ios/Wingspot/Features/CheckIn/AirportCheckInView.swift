import Account
import Persistence
import ReferenceData
import SwiftData
import SwiftUI
import WingspotCore

extension VisitContext {
    var title: LocalizedStringResource {
        switch self {
        case .spotting: "Spotting"
        case .departing: "Departing"
        case .arriving: "Arriving"
        case .transit: "Transit"
        case .working: "Working"
        case .museum: "Museum or airshow"
        }
    }
}

/// The Airport check-in (concept §4.3). Like Spotted, it saves on the device first and works offline.
struct AirportCheckInView: View {
    let onDone: () -> Void

    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(\.modelContext) private var modelContext
    @Environment(AccountStore.self) private var account
    @Environment(CheckInSyncCoordinator.self) private var sync: CheckInSyncCoordinator?

    @State private var airport: Airport?
    @State private var airportWasChosen = false
    @State private var context = VisitContext.spotting
    @State private var position: GeoCoordinate?
    @State private var result: AirportResult?
    @State private var saveFailed = false
    @State private var photo: PreparedPhoto?
    @State private var isPreparingPhoto = false

    var body: some View {
        Group {
            if let result {
                AirportResultView(result: result, onDone: onDone)
            } else {
                form
            }
        }
        .navigationTitle("Airport")
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
                NavigationLink {
                    AirportSearchView(selection: Binding(
                        get: { airport },
                        set: { airport = $0; airportWasChosen = true }
                    ))
                } label: {
                    LabeledContent("Airport", value: airport.map { "\($0.code) · \($0.name)" } ?? String(localized: "Choose"))
                }
                Picker("Reason", selection: $context) {
                    ForEach(VisitContext.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } footer: {
                if referenceData.database == nil {
                    if referenceData.isUpdating {
                        Text("Downloading aircraft and airport data.")
                    } else {
                        Text("Choosing an airport needs one download while online.")
                    }
                } else if airport == nil {
                    Text("Choose the airport you are at.")
                }
            }

            PhotoSection(photo: $photo, isPreparing: $isPreparingPhoto)

            Section {
                Button("Check in", action: save)
                    .disabled(airport == nil || isPreparingPhoto)
            }
        }
    }

    private func save() {
        guard let airport else { return }
        let draft = AirportDraft(airportID: airport.id, code: airport.code, context: context, position: position, photo: photo)
        do {
            result = try CheckInStore(context: modelContext).saveAirport(draft, ownerID: account.userID)
            sync?.requestSync()
        } catch {
            saveFailed = true
        }
    }

    private func suggestAirport() async {
        guard !airportWasChosen, let position, let database = referenceData.database else { return }
        airport = try? await database.nearestAirport(to: position)
    }

    private struct NearestKey: Hashable {
        let position: GeoCoordinate?
        let dataVersion: String?
    }
}

private struct AirportResultView: View {
    let result: AirportResult
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: isFirstTime ? "sparkles" : "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(result.code)
                    .font(.system(.largeTitle, design: .monospaced).bold())
                Text(headline)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                if case .visitedBefore(_, let lastVisit) = result.history {
                    Text("Last time on \(lastVisit.formatted(date: .abbreviated, time: .omitted))")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            Spacer()
            Button(action: onDone) {
                Text("Done").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .sensoryFeedback(.success, trigger: result.id)
    }

    private var isFirstTime: Bool { result.history == .firstTime }

    private var headline: LocalizedStringResource {
        switch result.history {
        case .firstTime: "First time at this airport!"
        case .visitedBefore(let count, _): "Visit number \(count)"
        }
    }
}
