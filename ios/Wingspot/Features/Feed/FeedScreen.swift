import Account
import Persistence
import SwiftData
import SwiftUI
import WingspotCore

/// The Feed tab: your check-ins and those of the people you follow, newest first.
struct FeedScreen: View {
    @Environment(AccountStore.self) private var account
    @Environment(FeedStore.self) private var feed
    @State private var commentsFor: FeedItem?
    @State private var report: ReportTarget?
    @Environment(TermsStore.self) private var terms
    @Environment(PushRouter.self) private var router
    @State private var personToOpen: OpenPerson?
    @Environment(CheckInSyncCoordinator.self) private var sync: CheckInSyncCoordinator?
    /// The flights saved on this device. Only these can be edited, because the details are sent from here.
    @Query(filter: #Predicate<LocalCheckIn> { $0.kind == "flown" }) private var localFlights: [LocalCheckIn]
    @State private var editing: EditedFlight?
    @State private var deleting: FeedItem?
    @State private var deleteFailed = false
    @Environment(\.modelContext) private var modelContext

    private struct EditedFlight: Identifiable { let id: UUID }

    private struct OpenPerson: Identifiable, Hashable { let id: UUID }

    var body: some View {
        NavigationStack {
            content
            .tabHeader("Feed") {
                if account.userID != nil, terms.hasAccepted {
                    NavigationLink { PeopleView() } label: { Image(systemName: "person.badge.plus") }
                        .accessibilityLabel("Find people")
                }
            }
            .navigationDestination(item: $commentsFor) { CheckInDetailView(item: $0) }
            .navigationDestination(item: $personToOpen) { PersonLoaderView(id: $0.id) }
            .sheet(item: $report) { ReportSheet(target: $0) }
            .confirmationDialog("Delete this check-in?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    guard let item = deleting else { return }
                    deleting = nil
                    Task { deleteFailed = !(await CheckInDeletion.delete(item.id, feed: feed, context: modelContext)) }
                }
            } message: {
                Text("It is removed for good, with its photos, salutes and comments.")
            }
            .alert("Couldn't delete this check-in", isPresented: $deleteFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please check your connection and try again.")
            }
            .sheet(item: $editing) { flight in
                FlownEditView(flightID: flight.id) {
                    Task {
                        await sync?.waitUntilIdle()
                        await feed.refresh()
                    }
                }
            }
        }
        .task(id: account.userID) {
            if account.userID == nil {
                feed.clear()
            } else {
                await feed.refresh()
            }
            await openPushDestination()
        }
        .onChange(of: router.destination) { Task { await openPushDestination() } }
    }

    @ViewBuilder private var content: some View {
        Group {
            if account.userID == nil {
                ContentUnavailableView {
                    Label("Your feed", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Sign in from the Profile tab to see check-ins from people you follow.")
                }
            } else if !terms.hasAccepted {
                TermsScreen { terms.accept() }
            } else if !feed.hasLoaded {
                if let failure = feed.failure {
                    ContentUnavailableView {
                        Label("Couldn't load your feed", systemImage: "wifi.slash")
                    } description: {
                        Text(failure.message)
                    } actions: {
                        Button("Try again") { Task { await feed.refresh() } }
                    }
                } else {
                    ProgressView()
                }
            } else if feed.items.isEmpty {
                ContentUnavailableView {
                    Label("Your feed is empty", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Check-ins from you and the people you follow appear here. Your check-ins show once they are uploaded and shared.")
                } actions: {
                    NavigationLink("Find people") { PeopleView() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                list
            }
        }
    }

    /// Opens what a tapped notification points at. A check-in that can't be seen any more opens nothing.
    private func openPushDestination() async {
        guard let destination = router.destination, account.userID != nil, terms.hasAccepted else { return }
        router.destination = nil
        switch destination {
        case .person(let id):
            personToOpen = OpenPerson(id: id)
        case .checkIn(let id):
            // The check-in may be older than the pages loaded, or someone else's, so it is asked for by id.
            if let known = feed.items.first(where: { $0.id == id }) {
                commentsFor = known
            } else {
                commentsFor = await feed.checkIn(id)
            }
        }
    }

    private var list: some View {
        let visible = feed.items.withoutAirportsOfListedFlights()
        let editable = Set(localFlights.map(\.id))
        return List {
            if let failure = feed.failure {
                Label(failure.message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(visible) { item in
                FeedCard(
                    item: item, isOwn: item.userID == account.userID, photos: feed.photos[item.id] ?? [],
                    onSalute: { Task { await feed.toggleSalute(item.id) } },
                    onOpen: { commentsFor = item },
                    onReport: { report = ReportTarget(kind: .checkin, id: item.id, subject: "this check-in") },
                    onReportPhoto: { report = ReportTarget(kind: .photo, id: $0.id, subject: "this photo") },
                    onEdit: item.userID == account.userID && editable.contains(item.id) ? { editing = EditedFlight(id: item.id) } : nil,
                    onDelete: item.userID == account.userID ? { deleting = item } : nil
                )
                    .task {
                        // Close to the end: ask for older check-ins.
                        if item.id == visible.dropLast(5).last?.id || item.id == visible.last?.id {
                            await feed.loadMore()
                        }
                    }
            }
            if feed.isLoading {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .refreshable { await feed.refresh() }
    }
}

struct FeedCard: View {
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometres
    let item: FeedItem
    let isOwn: Bool
    let photos: [FeedPhoto]
    let onSalute: () -> Void
    let onOpen: () -> Void
    let onReport: () -> Void
    let onReportPhoto: (FeedPhoto) -> Void
    /// Set for your own flights that can be edited.
    var onEdit: (() -> Void)?
    /// Set for your own check-ins.
    var onDelete: (() -> Void)?
    @State private var viewing: FeedPhoto?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                if isOwn {
                    Text("You").font(.subheadline.bold())
                } else {
                    NavigationLink { PersonLoaderView(id: item.userID) } label: {
                        Text(verbatim: item.displayName ?? item.username).font(.subheadline.bold())
                    }
                }
                Spacer()
                Text(item.occurredAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !isOwn || onEdit != nil || onDelete != nil {
                    Menu {
                        if let onEdit {
                            Button("Edit details", systemImage: "pencil", action: onEdit)
                        }
                        if let onDelete {
                            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                        }
                        if !isOwn {
                            Button("Report", systemImage: "flag", action: onReport)
                        }
                    } label: {
                        // A full-size touch target: the dots alone are too small to hit reliably.
                        Image(systemName: "ellipsis")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .padding(.trailing, -10)
                    .accessibilityLabel("More")
                }
            }
            Label(kindTitle, systemImage: kindSymbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            if item.kind == "airport", let airportID = item.airportID {
                NavigationLink { AirportPageView(airportID: airportID) } label: {
                    Text(verbatim: title)
                        .font(.system(.title3, design: .monospaced, weight: .semibold))
                }
            } else if item.kind == "spotted", let registration = item.registration {
                NavigationLink { RegistrationPageView(registration: registration) } label: {
                    Text(verbatim: title)
                        .font(.system(.title3, design: .monospaced, weight: .semibold))
                }
            } else if item.kind == "spotted", let type = item.typeICAO {
                NavigationLink { TypePageView(typeCode: type) } label: {
                    Text(verbatim: title)
                        .font(.system(.title3, design: .monospaced, weight: .semibold))
                }
            } else {
                Text(verbatim: title)
                    .font(.system(.title3, design: .monospaced, weight: .semibold))
            }
            if let detail {
                Text(verbatim: detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !photos.isEmpty {
                photoStrip
            }
            HStack(spacing: 20) {
                Button(action: onSalute) {
                    Label("\(item.salutes)", systemImage: item.saluted ? "hands.clap.fill" : "hands.clap")
                }
                .accessibilityLabel(item.saluted ? "Remove your salute. Salutes: \(item.salutes)" : "Salute. Salutes: \(item.salutes)")
                Button(action: onOpen) {
                    Label("\(item.comments)", systemImage: "bubble.left")
                }
                .accessibilityLabel("Comments: \(item.comments)")
            }
            .font(.subheadline)
            .buttonStyle(.borderless)
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .fullScreenCover(item: $viewing) { PhotoViewer(photos: photos, start: $0) }
    }

    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(photos) { photo in
                    AsyncImage(url: photo.url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            Image(systemName: "photo").foregroundStyle(.secondary)
                        default:
                            ProgressView()
                        }
                    }
                    .frame(width: photos.count == 1 ? 300 : 240, height: 200)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Photo")
                    .accessibilityAddTraits(.isButton)
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                    .onTapGesture { viewing = photo }
                    .contextMenu {
                        if !isOwn {
                            Button("Report photo", systemImage: "flag") { onReportPhoto(photo) }
                        }
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    private var kindTitle: LocalizedStringKey {
        switch item.kind {
        case "flown": "Flown"
        case "airport": "Airport"
        default: "Spotted"
        }
    }

    private var kindSymbol: String {
        switch item.kind {
        case "flown": "airplane"
        case "airport": "building.columns"
        default: "binoculars"
        }
    }

    /// The registration if there is one, otherwise the type. A flight shows its route.
    private var title: String {
        switch item.kind {
        case "airport": return item.airportCode ?? "?"
        case "flown": return "\(item.originCode ?? "?") → \(item.destinationCode ?? "?")"
        default: return item.registration ?? item.typeICAO ?? "?"
        }
    }

    private var detail: String? {
        switch item.kind {
        case "airport":
            return nil
        case "flown":
            let distance = item.distanceKm.map { unit.format(km: $0) }
            let parts = [item.flightNumber, item.registration ?? item.typeName, distance].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        default:
            let parts = [item.typeName ?? (item.registration == nil ? nil : item.typeICAO), item.airportCode].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }
}

/// Opens a person's page from just their ID, as in the feed.
struct PersonLoaderView: View {
    let id: UUID

    @Environment(SocialStore.self) private var social
    @State private var person: Person?
    @State private var failed = false

    var body: some View {
        Group {
            if let person {
                PersonDetailView(person: person)
            } else if failed {
                ContentUnavailableView("Couldn't load this profile", systemImage: "person.crop.circle.badge.questionmark")
            } else {
                ProgressView()
            }
        }
        .task {
            if let loaded = try? await social.person(id) { person = loaded } else { failed = true }
        }
    }
}
