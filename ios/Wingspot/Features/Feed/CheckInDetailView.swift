import Account
import Persistence
import SwiftData
import SwiftUI
import WingspotCore

/// One check-in on its own page: who, when and what, the photos, salute, and the comments with a field to write a new one.
struct CheckInDetailView: View {
    /// The check-in as it was when the page opened. The list it comes from has the current counts, see `current`.
    let item: FeedItem
    /// The list the check-in comes from, so its counts follow. The Feed tab's list if `nil`.
    var source: FeedStore?

    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometres
    @Environment(AccountStore.self) private var account
    @Environment(FeedStore.self) private var feed
    @Environment(CheckInSyncCoordinator.self) private var sync: CheckInSyncCoordinator?
    /// Your flights saved on this device. Only these can be edited, because the details are sent from here.
    @Query(filter: #Predicate<LocalCheckIn> { $0.kind == "flown" }) private var localFlights: [LocalCheckIn]
    @State private var viewing: FeedPhoto?
    @State private var editing = false
    @State private var full: FeedItem?
    @State private var store: CheckInCommentStore?
    @State private var text = ""
    @State private var problem: AccountError?
    @State private var report: ReportTarget?

    var body: some View {
        Group {
            if let store {
                content(store)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Check-in")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let created = (source ?? feed).commentStore(for: item.id)
            store = created
            async let loaded: Void = created.load()
            full = await (source ?? feed).checkIn(item.id)
            await loaded
        }
    }

    private var list: FeedStore { source ?? feed }
    private var current: FeedItem { list.items.first { $0.id == item.id } ?? item }
    /// The check-in as loaded by id, which has the airports of a flight, with the counts of the list.
    private var shown: FeedItem {
        guard let full else { return current }
        return full.updating(salutes: current.salutes, comments: current.comments, saluted: current.saluted)
    }
    private var photos: [FeedPhoto] { list.photos[item.id] ?? [] }
    private var isOwn: Bool { item.userID == account.userID }
    private var canEdit: Bool { isOwn && item.kind == "flown" && localFlights.contains { $0.id == item.id } }

    private func content(_ store: CheckInCommentStore) -> some View {
        List {
            summary
            if !photos.isEmpty { photoSection }
            reactions
            actions
            if store.isLoading, !store.hasLoaded {
                ProgressView().frame(maxWidth: .infinity)
            } else if let failure = store.failure, !store.hasLoaded {
                Text(failure.message).foregroundStyle(.secondary)
            } else if store.comments.isEmpty {
                Text("No comments yet").foregroundStyle(.secondary)
            }
            ForEach(store.comments) { comment in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: comment.displayName ?? comment.username).font(.subheadline.bold())
                        Spacer()
                        Text(comment.createdAt, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(verbatim: comment.body)
                }
                .accessibilityElement(children: .combine)
                .swipeActions {
                    // Your own comments, and any comment under your own check-in.
                    if comment.userID == account.userID || item.userID == account.userID {
                        Button("Delete", role: .destructive) { Task { await store.delete(comment) } }
                    }
                    if comment.userID != account.userID {
                        Button("Report") {
                            report = ReportTarget(kind: .comment, id: comment.id, subject: "this comment")
                        }
                        .tint(.orange)
                    }
                }
            }
        }
        .refreshable { await store.load() }
        .sheet(item: $report) { ReportSheet(target: $0) }
        .fullScreenCover(item: $viewing) { PhotoViewer(photos: photos, start: $0) }
        .sheet(isPresented: $editing) {
            FlownEditView(flightID: item.id) {
                Task {
                    await sync?.waitUntilIdle()
                    await list.refresh()
                }
            }
        }
        .safeAreaInset(edge: .bottom) { composer(store) }
        .alert("Couldn't complete this", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            if let problem { Text(problem.message) }
        }
    }

    // MARK: - The check-in

    private var summary: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                if isOwn {
                    Text("You").font(.subheadline.bold())
                } else {
                    NavigationLink { PersonLoaderView(id: shown.userID) } label: {
                        Text(verbatim: shown.displayName ?? shown.username).font(.subheadline.bold())
                    }
                }
                Label(kindTitle, systemImage: kindSymbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(verbatim: title)
                    .font(.system(.largeTitle, design: .monospaced, weight: .semibold))
                Text(shown.occurredAt, format: .dateTime.day().month(.wide).year().hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            if let airportID = shown.airportID, shown.kind == "airport" {
                NavigationLink { AirportPageView(airportID: airportID) } label: {
                    Label("Airport page", systemImage: "building.columns")
                }
            }
            if shown.kind == "flown" {
                if let origin = shown.originID, let destination = shown.destinationID {
                    NavigationLink { AirportPageView(airportID: origin) } label: {
                        LabeledContent("From", value: shown.originCode ?? "?")
                    }
                    NavigationLink { AirportPageView(airportID: destination) } label: {
                        LabeledContent("To", value: shown.destinationCode ?? "?")
                    }
                }
                if let number = shown.flightNumber { LabeledContent("Flight", value: number) }
                if let cabin = shown.cabin.flatMap(CabinClass.init(rawValue:)) { LabeledContent("Cabin", value: String(localized: cabin.title)) }
                if let seat = shown.seat { LabeledContent("Seat", value: seat) }
                if let km = shown.distanceKm { LabeledContent("Distance", value: unit.format(km: km)) }
            }
            if let registration = shown.registration {
                NavigationLink { RegistrationPageView(registration: registration) } label: {
                    LabeledContent("Aircraft", value: registration)
                }
            }
            if let type = shown.typeICAO {
                NavigationLink { TypePageView(typeCode: type) } label: {
                    LabeledContent("Type", value: shown.typeName ?? type)
                }
            }
            if shown.kind == "spotted", let airport = shown.airportCode, let airportID = shown.airportID {
                NavigationLink { AirportPageView(airportID: airportID) } label: {
                    LabeledContent("Airport", value: airport)
                }
            }
        }
    }

    private var photoSection: some View {
        Section {
            ForEach(photos) { photo in
                AsyncImage(url: photo.url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .failure:
                        Image(systemName: "photo").foregroundStyle(.secondary)
                    default:
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("Photo")
                .accessibilityAddTraits(.isButton)
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .onTapGesture { viewing = photo }
                .contextMenu {
                    if !isOwn {
                        Button("Report photo", systemImage: "flag") {
                            report = ReportTarget(kind: .photo, id: photo.id, subject: "this photo")
                        }
                    }
                }
            }
        }
    }

    private var reactions: some View {
        Section {
            Button {
                Task { await list.toggleSalute(shown.id) }
            } label: {
                Label("\(current.salutes)", systemImage: current.saluted ? "hands.clap.fill" : "hands.clap")
            }
            .accessibilityLabel(current.saluted ? "Remove your salute. Salutes: \(current.salutes)" : "Salute. Salutes: \(current.salutes)")
        }
    }

    /// Edit and look up your own flight, or report someone else's check-in.
    @ViewBuilder private var actions: some View {
        if canEdit {
            Section {
                Button("Edit details", systemImage: "pencil") { editing = true }
            }
        } else if !isOwn {
            Section {
                Button("Report", systemImage: "flag") {
                    report = ReportTarget(kind: .checkin, id: shown.id, subject: "this check-in")
                }
            }
        }
    }

    private var kindTitle: LocalizedStringKey {
        switch shown.kind {
        case "flown": "Flown"
        case "airport": "Airport"
        default: "Spotted"
        }
    }

    private var kindSymbol: String {
        switch shown.kind {
        case "flown": "airplane"
        case "airport": "building.columns"
        default: "binoculars"
        }
    }

    /// The registration if there is one, otherwise the type. A flight shows its route.
    private var title: String {
        switch shown.kind {
        case "airport": return shown.airportCode ?? "?"
        case "flown": return "\(shown.originCode ?? "?") → \(shown.destinationCode ?? "?")"
        default: return shown.registration ?? shown.typeICAO ?? "?"
        }
    }

    private func composer(_ store: CheckInCommentStore) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Write a comment…", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
            Button {
                send(store)
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .accessibilityLabel("Send")
            .disabled(!CheckInCommentStore.isSendable(text) || store.isSending)
        }
        .padding()
        .background(.bar)
    }

    private func send(_ store: CheckInCommentStore) {
        let draft = text
        Task {
            do {
                try await store.send(draft)
                text = ""
            } catch {
                problem = (error as? AccountError) ?? .unknown
            }
        }
    }
}
