import Account
import SwiftUI

/// Suggest a new spotting location. It waits for approval and only its author sees it until then.
struct AddSpotView: View {
    let onAdded: () -> Void

    @Environment(SpotStore.self) private var spots
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var position: (latitude: Double, longitude: Double)?
    @State private var link = ""
    @State private var about = ""
    @State private var bestTime = ""
    @State private var facing = ""
    @State private var tips = ""
    @State private var isSending = false
    @State private var message: LocalizedStringResource?
    @State private var linkNotUnderstood = false

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { trimmedName.count >= 3 && position != nil && !isSending }

    var body: some View {
        Form {
            Section {
                TextField("Name, e.g. Visitor terrace", text: $name)
            }
            Section {
                TextField("Link or coordinates from a maps app", text: $link)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: link) { _, text in readLink(text) }
                if let position {
                    LabeledContent("Position") {
                        Text(verbatim: String(format: "%.5f, %.5f", position.latitude, position.longitude)).foregroundStyle(.secondary)
                    }
                } else if linkNotUnderstood {
                    Text("This doesn't contain a position. Open the place in the maps app and copy its full link, or the coordinates.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Where is it?")
            } footer: {
                Text("In Google Maps, press and hold the place, then copy the coordinates or share the link. The airport nearest to it is added for you.")
            }
            Section {
                TextField("About this place", text: $about, axis: .vertical)
                TextField("Best time", text: $bestTime)
                TextField("Facing, e.g. south-west", text: $facing)
                TextField("Tips: facilities, parking, lenses", text: $tips, axis: .vertical)
            } header: {
                Text("Optional")
            }
            Section {
                Button("Suggest this place", action: send).disabled(!canSend)
            } footer: {
                Text("A new place waits for approval. Until then only you can see it and check in there.")
            }
        }
        .navigationTitle("Suggest a place")
        .navigationBarTitleDisplayMode(.inline)
        .alert(message.map { String(localized: $0) } ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private func readLink(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { linkNotUnderstood = false; return }
        if let found = MapsLink.coordinate(in: text) {
            position = found
            linkNotUnderstood = false
        } else {
            linkNotUnderstood = true
        }
    }

    private func send() {
        guard let position else { return }
        isSending = true
        Task {
            defer { isSending = false }
            func optional(_ text: String) -> String? {
                let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
            let request = NewSpot(
                name: trimmedName, latitude: position.latitude, longitude: position.longitude, description: optional(about),
                bestTime: optional(bestTime), facing: optional(facing), tips: optional(tips)
            )
            guard let answer = try? await spots.add(request) else {
                message = "Couldn't send this. Check your connection and try again."
                return
            }
            switch answer.status {
            case "pending":
                onAdded()
                dismiss()
            case "duplicate":
                message = "This place is already there."
            default:
                switch answer.code {
                case "no_airport_nearby": message = "There is no airport within 150 km of this position."
                case "too_many_pending": message = "You already have ten places waiting for approval. Please wait until some are approved."
                case "invalid_name": message = "The name needs 3 to 80 characters."
                default: message = "This place couldn't be added."
                }
            }
        }
    }
}
