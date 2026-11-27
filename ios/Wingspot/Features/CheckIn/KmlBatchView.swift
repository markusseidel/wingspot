import Account
import Persistence
import ReferenceData
import SwiftData
import SwiftUI
import WingspotCore

/// Several KML files at once (#236): one list with a row per file, the ones that can be used ticked, and one button that saves them all as
/// flights, each with its route, which stays on this iPhone. Nothing is saved before the person confirms.
struct KmlBatchView: View {
    let urls: [URL]
    let onDone: () -> Void

    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(AccountStore.self) private var account
    @Environment(\.modelContext) private var modelContext
    @Environment(CheckInSyncCoordinator.self) private var sync: CheckInSyncCoordinator?
    @Environment(AutoBackup.self) private var autoBackup: AutoBackup?

    private struct Row: Identifiable {
        enum State: Equatable {
            case ready, duplicate
            /// Why it can't be used: the file, the route or the day.
            case problem(LocalizedStringResource)
        }
        let id = UUID()
        let name: String
        var state: State
        var flight: KmlFlight?
        var origin: Airport?
        var destination: Airport?
        var type: AircraftType?
        var day: Date?
    }

    @State private var rows: [Row] = []
    @State private var isLoading = true
    @State private var selected: Set<UUID> = []
    @State private var added: Int?
    @State private var failed = false

    var body: some View {
        List {
            if let added {
                Section {
                    Label("Added \(added) flights.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Button("Done", action: onDone)
                }
            } else if isLoading {
                Section { HStack { ProgressView(); Text("Reading the files…").padding(.leading, 8) } }
            } else {
                Section {
                    ForEach(rows) { row in rowView(row) }
                } header: {
                    Text("\(rows.count) files")
                } footer: {
                    Text("Ticked flights are added to your logbook. A flight you already have is not ticked. The routes stay on this iPhone.")
                }
                Section {
                    Button("Add \(selected.count) flights", action: save).disabled(selected.isEmpty)
                }
            }
        }
        .navigationTitle("KML files")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onDone() } } }
        .alert("Couldn't save the flights", isPresented: $failed) { Button("OK", role: .cancel) {} } message: { Text("Please try again.") }
        .task { await load() }
    }

    private func isUsable(_ row: Row) -> Bool {
        row.state == .ready || row.state == .duplicate
    }

    private func toggle(_ row: Row) {
        guard isUsable(row) else { return }
        if selected.contains(row.id) { selected.remove(row.id) } else { selected.insert(row.id) }
    }

    private func rowView(_ row: Row) -> some View {
        Button { toggle(row) } label: {
            HStack(alignment: .top) {
                checkbox(row)
                VStack(alignment: .leading, spacing: 2) {
                    title(row)
                    Text(verbatim: details(row)).font(.subheadline).foregroundStyle(.secondary)
                    note(row)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func checkbox(_ row: Row) -> some View {
        let name: String = selected.contains(row.id) ? "checkmark.circle.fill" : "circle"
        let color: Color = isUsable(row) ? Color.accentColor : Color.gray.opacity(0.4)
        return Image(systemName: name).foregroundColor(color)
    }

    @ViewBuilder private func title(_ row: Row) -> some View {
        if let from = row.origin, let to = row.destination {
            Text(verbatim: from.code + " → " + to.code).font(.headline)
        } else {
            Text(verbatim: row.name).font(.headline)
        }
    }

    @ViewBuilder private func note(_ row: Row) -> some View {
        switch row.state {
        case .ready:
            EmptyView()
        case .duplicate:
            Text("Already in your logbook").font(.footnote).foregroundColor(.orange)
        case .problem(let message):
            Text(message).font(.footnote).foregroundColor(.red)
        }
    }

    private func details(_ row: Row) -> String {
        var parts: [String] = []
        if let number = row.flight?.flightNumber { parts.append(number) }
        if let day = row.day { parts.append(day.formatted(date: .abbreviated, time: .omitted)) }
        if let registration = row.flight?.registration { parts.append(registration) }
        return parts.joined(separator: " · ")
    }

    /// Reads every file one after the other, looks up the airports and the type, and marks what is already there.
    private func load() async {
        var found: [Row] = []
        for url in urls {
            let name = url.deletingPathExtension().lastPathComponent
            switch await KmlImport.read(url) {
            case .failure:
                let message: LocalizedStringResource = "Not a KML file of a flight"
                found.append(Row(name: name, state: .problem(message)))
            case .success(let flight):
                var row = Row(name: name, state: .ready, flight: flight, day: flight.departureDay())
                if let database = referenceData.database {
                    if let code = flight.origin?.iata { row.origin = try? await database.airport(iata: code) }
                    if let code = flight.destination?.iata { row.destination = try? await database.airport(iata: code) }
                    if let code = flight.aircraftTypeCode { row.type = try? await database.aircraftType(icao: code) }
                }
                let noRoute = row.origin == nil || row.destination == nil || row.origin?.id == row.destination?.id
                if noRoute {
                    let message: LocalizedStringResource
                    if referenceData.database == nil {
                        message = "Airport data is not downloaded yet"
                    } else {
                        message = "No route found in the file"
                    }
                    row.state = .problem(message)
                } else if row.day == nil {
                    let message: LocalizedStringResource = "No date found in the file"
                    row.state = .problem(message)
                }
                found.append(row)
            }
        }
        // Oldest flight first, the files without a day at the end.
        found.sort { (a: Row, b: Row) -> Bool in (a.day ?? Date.distantFuture) < (b.day ?? Date.distantFuture) }
        let owner = account.userID
        let descriptor = FetchDescriptor<LocalCheckIn>(predicate: #Predicate { $0.kind == "flown" && $0.ownerID == owner })
        let mine: [LocalCheckIn] = (try? modelContext.fetch(descriptor)) ?? []
        var entries: [KmlBatch.Entry] = []
        for row in found {
            entries.append(KmlBatch.Entry(flightNumber: row.flight?.flightNumber, day: row.day, link: row.flight?.flightLink))
        }
        var existing: [KmlBatch.Existing] = []
        for flight in mine {
            existing.append(KmlBatch.Existing(flightNumber: flight.flightNumber, day: flight.occurredAt))
        }
        let flags = KmlBatch.duplicates(in: entries, existing: existing)
        for index in found.indices where found[index].state == .ready && flags[index] { found[index].state = .duplicate }
        rows = found
        selected = Set(found.filter { $0.state == .ready }.map(\.id))
        isLoading = false
    }

    private func save() {
        let store = CheckInStore(context: modelContext)
        var count = 0
        for row in rows where selected.contains(row.id) {
            guard let flight = row.flight, let origin = row.origin, let destination = row.destination, let day = row.day else { continue }
            let distance = GreatCircle.distanceKm(from: origin.coordinate, to: destination.coordinate)
            let registration = flight.registration.flatMap { Registration($0) }
            let draft = FlownDraft(
                origin: .init(airportID: origin.id, code: origin.code), destination: .init(airportID: destination.id, code: destination.code),
                distanceKm: Int(distance.rounded()), flightNumber: flight.flightNumber, registration: registration,
                type: row.type.map { .init(icaoCode: $0.icaoCode, name: $0.name) }
            )
            do {
                let saved = try store.saveFlown(draft, ownerID: account.userID, at: FlightDay.moment(of: day))
                if flight.track.count >= 2 { try? FlightTrackFiles.standard.save(flight.track, for: saved.id) }
                count += 1
            } catch {
                failed = true
            }
        }
        sync?.requestSync()
        autoBackup?.schedule()
        if count > 0 { added = count }
    }
}
