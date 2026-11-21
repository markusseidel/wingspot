import Account
import MapKit
import SwiftUI

/// Spotting locations: the places at an airport, one place, and the aircraft of a session.
@MainActor
@Observable
final class SpotStore {
    private let backend: any SpotBackend

    init(backend: any SpotBackend) {
        self.backend = backend
    }

    func locations(at airport: Int) async -> [SpotLocation] { (try? await backend.spotLocations(at: airport)) ?? [] }
    func detail(_ id: Int) async -> SpotDetail? { try? await backend.spotDetail(id) }
    func sightings(of visit: UUID) async -> [VisitSighting] { (try? await backend.visitSightings(visit)) ?? [] }
    func spot(of checkIn: UUID) async -> CheckInSpot? { (try? await backend.checkInSpot(checkIn)) ?? nil }
}

/// The spotting locations of an airport, as a section of its page. Nothing is shown when there are none.
/// The parent loads the places, because a view with nothing in it never runs its own task.
struct AirportSpotsSection: View {
    let locations: [SpotLocation]

    var body: some View {
        if !locations.isEmpty {
            Section {
                ForEach(locations) { place in
                    NavigationLink { SpotPageView(id: place.id) } label: { SpotRow(place: place) }
                }
            } header: {
                Text("Spotting locations")
            }
        }
    }
}

private struct SpotRow: View {
    let place: SpotLocation

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: place.name)
            if place.isPending {
                Text("Waiting for approval").font(.footnote).foregroundStyle(.secondary)
            } else if place.sessions > 0 {
                Text("Sessions: \(place.sessions)").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One spotting location: where it is, what to know before going, and how much it is used.
struct SpotPageView: View {
    let id: Int
    @Environment(SpotStore.self) private var spots
    @State private var detail: SpotDetail?
    @State private var loaded = false

    var body: some View {
        List {
            if let detail {
                header(detail)
                numbers(detail)
                tips(detail)
            } else if loaded {
                Section {
                    Label("This place isn't available.", systemImage: "mappin.slash").foregroundStyle(.secondary)
                }
            } else {
                Section { ProgressView().frame(maxWidth: .infinity) }
            }
        }
        .navigationTitle(Text(verbatim: detail?.name ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            detail = await spots.detail(id)
            loaded = true
        }
    }

    @ViewBuilder
    private func header(_ place: SpotDetail) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: place.name).font(.title3.bold())
                Text(verbatim: [place.iata, place.airport].compactMap { $0 }.joined(separator: " · ")).foregroundStyle(.secondary)
                if place.isPending {
                    Label("Waiting for approval. Only you can see this place.", systemImage: "clock").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            let center = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
            Map(initialPosition: .region(MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))),
                interactionModes: []) {
                Marker(place.name, coordinate: center)
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .accessibilityHidden(true)
            if let url = mapsURL(place) {
                Link(destination: url) { Label("Open in Maps", systemImage: "map") }
            }
        }
    }

    private func mapsURL(_ place: SpotDetail) -> URL? {
        var parts = URLComponents(string: "https://maps.apple.com/")
        parts?.queryItems = [
            URLQueryItem(name: "ll", value: "\(place.latitude),\(place.longitude)"),
            URLQueryItem(name: "q", value: place.name),
        ]
        return parts?.url
    }

    private func numbers(_ place: SpotDetail) -> some View {
        Section {
            LabeledContent("Sessions", value: "\(place.sessions)")
            LabeledContent("Aircraft seen", value: "\(place.aircraft)")
            LabeledContent("Your sessions", value: "\(place.mySessions)")
        } footer: {
            Text("Counts include only public check-ins and your own.")
        }
    }

    @ViewBuilder
    private func tips(_ place: SpotDetail) -> some View {
        let rows: [(LocalizedStringKey, String?)] = [
            ("About this place", place.description), ("Best time", place.bestTime), ("Facing", place.facing),
            ("Tips", place.tips), ("Good to know", place.legalNotes),
        ]
        let shown = rows.compactMap { title, text in text.flatMap { $0.isEmpty ? nil : (title, $0) } }
        if !shown.isEmpty {
            Section {
                ForEach(shown, id: \.1) { title, text in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.footnote).foregroundStyle(.secondary)
                        Text(verbatim: text)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// On a check-in page: the place of a session, and the aircraft seen during it.
/// The parent loads `spot` and `sightings`, because a view with nothing in it never runs its own task.
struct CheckInSpotSection: View {
    let spot: CheckInSpot?
    let sightings: [VisitSighting]
    let kind: String

    var body: some View {
        Group {
            if let spot {
                if let name = spot.spotName, let id = spot.spotID {
                    Section {
                        NavigationLink { SpotPageView(id: id) } label: {
                            Label {
                                Text(kind == "airport" ? "At \(name)" : "Spotted at \(name)")
                            } icon: {
                                Image(systemName: "binoculars")
                            }
                        }
                    }
                }
                if kind == "airport", !sightings.isEmpty {
                    Section {
                        ForEach(sightings) { sighting in
                            LabeledContent {
                                Text(sighting.occurredAt, format: .dateTime.hour().minute()).foregroundStyle(.secondary)
                            } label: {
                                Text(verbatim: [sighting.registration, sighting.typeICAO].compactMap { $0 }.joined(separator: " · "))
                            }
                        }
                    } header: {
                        Text("Aircraft seen").font(.headline).textCase(nil)
                    }
                }
            }
        }
    }
}
