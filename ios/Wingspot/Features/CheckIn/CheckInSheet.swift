import SwiftUI

enum CheckInKind: String, CaseIterable, Identifiable {
    case spotted, flown, airport

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .spotted: "Spotted"
        case .flown: "Flown"
        case .airport: "Airport"
        }
    }

    var subtitle: LocalizedStringResource {
        switch self {
        case .spotted: "An aircraft you have seen"
        case .flown: "A flight you were on"
        case .airport: "An airport you are at"
        }
    }

    var systemImage: String {
        switch self {
        case .spotted: "binoculars.fill"
        case .flown: "airplane.departure"
        case .airport: "building.columns.fill"
        }
    }
}

struct CheckInSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// A form a shortcut of the app icon asks for (#349): opened as soon as it is set, and cleared. The sheet may be open already.
    @Binding var requested: CheckInKind?
    @State private var path: [CheckInKind] = []

    /// A sheet that opens for a shortcut starts with the form already pushed. Pushing it a moment after the sheet appeared left a
    /// second, large title drawn over the form.
    init(requested: Binding<CheckInKind?> = .constant(nil)) {
        _requested = requested
        _path = State(initialValue: requested.wrappedValue.map { [$0] } ?? [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                SpotSessionRow()
                ForEach(CheckInKind.allCases) { kind in
                    NavigationLink(value: kind) {
                        Label {
                            VStack(alignment: .leading) {
                                Text(kind.title).font(.headline)
                                Text(kind.subtitle).font(.subheadline).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: kind.systemImage).foregroundStyle(.tint)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .navigationTitle("Check in")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: requested) {
                if let kind = requested {
                    if path != [kind] { path = [kind] }
                    requested = nil
                }
            }
            .navigationDestination(for: CheckInKind.self) { kind in
                switch kind {
                case .spotted:
                    SpottedCheckInView(onDone: { dismiss() })
                case .airport:
                    AirportCheckInView(onDone: { dismiss() })
                case .flown:
                    FlownCheckInView(onDone: { dismiss() })
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
