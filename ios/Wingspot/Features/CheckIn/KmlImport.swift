import Foundation
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
    case notKml, unreadable, tooLarge

    var id: Int { hashValue }
    var title: LocalizedStringResource {
        switch self {
        case .notKml: "This is not a KML file"
        case .unreadable: "Couldn't read the file"
        case .tooLarge: "The file is too large"
        }
    }
    var message: LocalizedStringResource {
        switch self {
        case .notKml: "Choose a KML file of one flight."
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
