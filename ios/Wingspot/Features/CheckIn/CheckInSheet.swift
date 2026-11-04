import SwiftUI

enum CheckInKind: String, CaseIterable, Identifiable {
    case spotted, flown, airport

    var id: Self { self }

    var title: String {
        switch self {
        case .spotted: "Spotted"
        case .flown: "Flown"
        case .airport: "Airport"
        }
    }

    var subtitle: String {
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

    var body: some View {
        NavigationStack {
            List(CheckInKind.allCases) { kind in
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
            .navigationTitle("Check in")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: CheckInKind.self) { kind in
                switch kind {
                case .spotted:
                    SpottedCheckInView(onDone: { dismiss() })
                case .flown, .airport:
                    ContentUnavailableView(kind.title, systemImage: kind.systemImage,
                                           description: Text("Coming in a later milestone."))
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
