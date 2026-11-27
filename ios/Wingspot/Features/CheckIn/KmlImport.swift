import Foundation
import Persistence
import ReferenceData
import SwiftUI
import UniformTypeIdentifiers
import WingspotCore

/// What the form shows after a KML file was read: which of the fields it could fill in and which not.
enum ImportedField: CaseIterable {
    case route, date, flightNumber, registration, aircraftType

    var title: LocalizedStringResource {
        switch self {
        case .route: "route"
        case .date: "date"
        case .flightNumber: "flight number"
        case .registration: "registration"
        case .aircraftType: "aircraft type"
        }
    }
}

struct ImportNotice: Equatable {
    var found: [ImportedField]
    var missing: [ImportedField]

    /// "route, date and flight number" in the language of the app.
    static func list(_ fields: [ImportedField]) -> String {
        ListFormatter.localizedString(byJoining: fields.map { String(localized: $0.title) })
    }
}

enum KmlImportProblem: Error, Identifiable {
    case notKml, unreadable, tooLarge, noRoute

    var id: Int { hashValue }
    var title: LocalizedStringResource {
        switch self {
        case .notKml: "This is not a KML file"
        case .unreadable: "Couldn't read the file"
        case .tooLarge: "The file is too large"
        case .noRoute: "This file has no route"
        }
    }
    var message: LocalizedStringResource {
        switch self {
        case .notKml, .noRoute: "Choose a KML file of one flight."
        case .unreadable: "Please try again, or choose another file."
        case .tooLarge: "Files above 50 MB are not read."
        }
    }
}

enum KmlImport {
    /// The biggest file that is read, in bytes.
    static let sizeLimit = 50_000_000

    /// Reads and parses a file the person picked. The file is read on this iPhone and nothing is sent anywhere.
    static func read(_ url: URL) async -> Result<KmlFlight, KmlImportProblem> {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > sizeLimit { return .failure(.tooLarge) }
        return await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url), data.count <= sizeLimit else { return .failure(.unreadable) }
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return .failure(.unreadable) }
            do { return .success(try KmlFlightParser.parse(text)) } catch { return .failure(.notKml) }
        }.value
    }

    /// How the flown route compares with the direct way, for the form: nil when there is no route or no detour.
    static func detour(track: [GeoCoordinate], origin: Airport?, destination: Airport?) -> (flownKm: Int, extraKm: Int, percent: Int)? {
        guard track.count >= 2 else { return nil }
        let flown = FlightTrack.lengthKm(track)
        guard let origin, let destination, origin.id != destination.id,
              let detour = FlightTrack.detour(flownKm: flown, greatCircleKm: GreatCircle.distanceKm(from: origin.coordinate, to: destination.coordinate)),
              detour.extraKm >= 1 else { return (Int(flown.rounded()), 0, 0) }
        return (Int(flown.rounded()), Int(detour.extraKm.rounded()), Int(detour.percent.rounded()))
    }
}

/// On the page of your own flight: adds the route from a KML file, or replaces the one that is saved. Nothing else on the
/// flight changes, and nothing is saved before the person confirms. The route stays on this iPhone.
struct RouteFromFileButton: View {
    let flightID: UUID
    let originCode: String?
    let destinationCode: String?
    let occurredAt: Date
    let hasRoute: Bool
    let onSaved: () -> Void

    @Environment(AutoBackup.self) private var autoBackup: AutoBackup?
    @State private var showImporter = false
    @State private var isReading = false
    @State private var problem: KmlImportProblem?
    @State private var pending: PendingRoute?

    private struct PendingRoute: Identifiable {
        let id = UUID()
        let track: [GeoCoordinate]
        let message: String
    }

    var body: some View {
        Button { showImporter = true } label: {
            let title: LocalizedStringResource = isReading ? "Reading…" : (hasRoute ? "Replace the route from a file" : "Add a route from a KML file")
            Label { Text(title) } icon: { Image(systemName: "doc.badge.arrow.up") }
        }
        .disabled(isReading)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data]) { picked in
            guard case .success(let url) = picked else { return }
            Task { await read(url) }
        }
        .confirmationDialog(
            hasRoute ? String(localized: "Replace the route?") : String(localized: "Save the route?"),
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible, presenting: pending
        ) { route in
            Button(hasRoute ? "Replace route" : "Save route") {
                try? FlightTrackFiles.standard.save(route.track, for: flightID)
                autoBackup?.schedule()
                onSaved()
            }
            Button("Cancel", role: .cancel) {}
        } message: { route in
            Text(verbatim: route.message)
        }
        .alert(problem.map { String(localized: $0.title) } ?? "", isPresented: Binding(
            get: { problem != nil }, set: { if !$0 { problem = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(problem.map { String(localized: $0.message) } ?? "")
        }
    }

    private func read(_ url: URL) async {
        isReading = true
        defer { isReading = false }
        switch await KmlImport.read(url) {
        case .failure(let failure):
            problem = failure
        case .success(let flight):
            guard flight.track.count >= 2 else { problem = .noRoute; return }
            pending = PendingRoute(track: flight.track, message: message(for: flight))
        }
    }

    /// What was found, and what does not fit this flight. Different airports or a different day are only a warning.
    private func message(for flight: KmlFlight) -> String {
        let flown = DistanceUnit.preferred.format(km: Int(FlightTrack.lengthKm(flight.track).rounded()))
        var lines = [String(localized: "Route found: \(flight.track.count) positions, \(flown) flown. The route stays on this iPhone.")]
        if let from = flight.origin?.iata, let to = flight.destination?.iata, let origin = originCode, let destination = destinationCode,
           from.caseInsensitiveCompare(origin) != .orderedSame || to.caseInsensitiveCompare(destination) != .orderedSame {
            lines.append(String(localized: "The file is for \(from) → \(to), but this flight is \(origin) → \(destination)."))
        }
        if let day = flight.departureDay(), abs(day.timeIntervalSince(occurredAt)) > 36 * 3600 {
            lines.append(String(localized: "The file is for a different day than this flight."))
        }
        if hasRoute { lines.append(String(localized: "This flight already has a route. It is replaced.")) }
        return lines.joined(separator: "\n\n")
    }
}
