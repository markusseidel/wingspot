import Account
import SwiftUI

/// The places that wait for a decision. Shown to people with the review permission.
struct SpotReviewView: View {
    @Environment(SpotStore.self) private var spots
    @State private var places: [PendingSpot]?
    @State private var rejecting: PendingSpot?
    @State private var note = ""
    @State private var message: LocalizedStringResource?

    var body: some View {
        List {
            if let places {
                if places.isEmpty {
                    Text("Nothing waits for review.").foregroundStyle(.secondary)
                }
                ForEach(places) { place in
                    SpotReviewRow(
                        place: place,
                        onApprove: { decide(place, approve: true, note: nil) },
                        onReject: { note = ""; rejecting = place }
                    )
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Review places")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .alert("Reject this place?", isPresented: Binding(get: { rejecting != nil }, set: { if !$0 { rejecting = nil } })) {
            TextField("Reason (shown to the author)", text: $note)
            Button("Reject", role: .destructive) {
                if let place = rejecting { decide(place, approve: false, note: note) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(message.map { String(localized: $0) } ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private func load() async { places = await spots.pending() ?? places ?? [] }

    private func decide(_ place: PendingSpot, approve: Bool, note: String?) {
        Task {
            let answer = await spots.review(place.id, approve: approve, note: note)
            switch answer?.code {
            case nil where answer?.status == "approved" || answer?.status == "rejected":
                places?.removeAll { $0.id == place.id }
            case "not_pending":
                message = "Someone else already decided on this place."
                places?.removeAll { $0.id == place.id }
            default:
                message = "Couldn't save the decision. Try again."
            }
        }
    }
}

private struct SpotReviewRow: View {
    let place: PendingSpot
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: place.name).font(.headline)
            Text(verbatim: "\(place.airportCode) · \(place.airportName)").font(.subheadline).foregroundStyle(.secondary)
            if let author = place.authorName ?? place.authorUsername {
                Text("Suggested by \(author)").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach([place.description, place.bestTime, place.facing, place.tips, place.legalNotes].compactMap { $0 }, id: \.self) { text in
                Text(verbatim: text).font(.footnote)
            }
            if let url = URL(string: "https://maps.apple.com/?ll=\(place.latitude),\(place.longitude)&q=\(place.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                Link(destination: url) { Label("Open in Maps", systemImage: "map") }.font(.footnote)
            }
            HStack {
                Button("Approve", action: onApprove).buttonStyle(.borderedProminent)
                Button("Reject", role: .destructive, action: onReject).buttonStyle(.bordered)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }
}
