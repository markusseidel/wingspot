import Account
import Persistence
import ReferenceData
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
    @Environment(BadgeStore.self) private var badges
    @Environment(ReferenceDataStore.self) private var referenceData
    @Environment(CheckInSyncCoordinator.self) private var sync: CheckInSyncCoordinator?
    /// Your check-ins saved on this device. Only these can be edited, because the details are sent from here.
    @Query private var localCheckIns: [LocalCheckIn]
    @State private var viewing: FeedPhoto?
    @State private var editing = false
    @State private var returnStart: ReturnStart?
    @State private var confirmDelete = false
    @State private var confirmLeave = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var full: FeedItem?
    @State private var store: CheckInCommentStore?
    @State private var text = ""
    @FocusState private var commentFocused: Bool
    @State private var problem: AccountError?
    @State private var report: ReportTarget?
    /// Friends who can be mentioned, loaded the first time an "@" is typed.
    @State private var friends: [PersonTag] = []
    @State private var friendsLoaded = false
    @State private var mentionedPerson: MentionedPerson?

    private struct MentionedPerson: Identifiable, Hashable { let id: UUID }

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
        .navigationDestination(item: $mentionedPerson) { PersonLoaderView(id: $0.id) }
        .environment(\.openURL, OpenURLAction { url in
            // A tapped @name in a comment carries the person's id.
            guard url.scheme == "wingspot-person", let host = url.host, let id = UUID(uuidString: host) else { return .systemAction }
            mentionedPerson = MentionedPerson(id: id)
            return .handled
        })
        .task {
            let created = (source ?? feed).commentStore(for: item.id)
            store = created
            async let loaded: Void = created.load()
            async let tagged: Void = (source ?? feed).reloadTags(for: item.id)
            full = await (source ?? feed).checkIn(item.id)
            await loaded
            await tagged
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
    private var tags: [PersonTag] { list.tags[item.id] ?? [] }
    private var earned: [FeedBadge] { list.badges[item.id] ?? [] }
    private var isTagged: Bool { tags.contains { $0.id == account.userID } }
    /// A friend's flight or airport visit that you are tagged on can be added to your own logbook, once.
    private var canCopy: Bool { !isOwn && isTagged && (shown.kind == "flown" || shown.kind == "airport") }
    private var inMyLogbook: Bool { localCheckIns.contains { $0.sourceID == item.id } }
    private var isOwn: Bool { item.userID == account.userID }
    private var canEdit: Bool { isOwn && localCheckIns.contains { $0.id == item.id } }

    private func content(_ store: CheckInCommentStore) -> some View {
        List {
            summary
            if !earned.isEmpty { Section { FeedBadgesLine(badges: earned) } header: { Text("Badges earned").font(.headline).textCase(nil) } }
            if !tags.isEmpty { withSection }
            if !photos.isEmpty { photoSection }
            reactions
            actions
            lookup
            commentsSection(store)
        }
        .refreshable { await store.load() }
        .sheet(item: $report) { ReportSheet(target: $0) }
        .fullScreenCover(item: $viewing) { PhotoViewer(photos: photos, start: $0) }
        .confirmationDialog("Delete this check-in?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    let others = source == nil ? [] : [feed]
                    if await CheckInDeletion.delete(item.id, feed: list, others: others, badges: badges, context: modelContext) {
                        dismiss()
                    } else {
                        problem = list.failure ?? .unknown
                    }
                }
            }
        } message: {
            Text("It is removed for good, with its photos, salutes and comments.")
        }
        .confirmationDialog("Remove yourself from this check-in?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Remove me", role: .destructive) {
                Task {
                    if await list.removeMyTag(item.id) {
                        // A private check-in can no longer be seen, so the page goes.
                        if await list.checkIn(item.id) == nil {
                            list.remove(item.id)
                            if source != nil { feed.remove(item.id) }
                            dismiss()
                        }
                    } else {
                        problem = list.failure ?? .unknown
                    }
                }
            }
        }
        .sheet(item: $returnStart) { start in
            NavigationStack {
                FlownCheckInView(start: start, onDone: { returnStart = nil })
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { returnStart = nil } }
                    }
            }
        }
        .sheet(isPresented: $editing) {
            let saved: () -> Void = {
                Task {
                    await sync?.waitUntilIdle()
                    await list.refresh()
                }
            }
            if item.kind == "flown" {
                FlownEditView(flightID: item.id, tags: tags, onSaved: saved)
            } else {
                CheckInEditView(checkInID: item.id, tags: tags, onSaved: saved)
            }
        }
        .scrollDismissesKeyboard(.interactively)
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

    /// The friends who were along, one row each, so a tap opens exactly one of them.
    private var withSection: some View {
        Section {
            ForEach(tags) { person in
                if person.id == account.userID {
                    friendRow(String(localized: "You"), id: person.id)
                } else {
                    NavigationLink { PersonLoaderView(id: person.id) } label: { friendRow(person.name, id: person.id) }
                }
            }
        } header: {
            Text("With").font(.headline).textCase(nil)
        }
    }

    private func friendRow(_ name: String, id: UUID) -> some View {
        HStack(spacing: 12) {
            AvatarView(id: id, name: name, size: 40)
            Text(verbatim: name).font(.body)
        }
        .padding(.vertical, 4)
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
        if isOwn {
            Section {
                if canEdit {
                    Button("Edit details", systemImage: "pencil") { editing = true }
                }
                if shown.kind == "flown", shown.originID != nil, shown.destinationID != nil {
                    Button("Return flight", systemImage: "arrow.uturn.backward") { Task { await prepareReturn() } }
                }
                Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
            Section { CheckInVisibilityPicker(checkInID: item.id) }
        } else {
            if canCopy {
                Section {
                    if inMyLogbook {
                        Label("In your logbook", systemImage: "checkmark.circle")
                    } else {
                        Button("Add to my logbook", systemImage: "plus.circle") { addToLogbook() }
                    }
                } footer: {
                    if !inMyLogbook { Text("Adds it to your own check-ins, so it counts for your statistics and badges.") }
                }
            }
            if isTagged {
                Section {
                    Button("Remove me from this check-in", systemImage: "person.crop.circle.badge.minus") { confirmLeave = true }
                } footer: {
                    Text("You won't be tagged on it again, and you won't see it any more unless it is public.")
                }
            }
            Section {
                Button("Report", systemImage: "flag") {
                    report = ReportTarget(kind: .checkin, id: shown.id, subject: "this check-in")
                }
            }
        }
    }

    /// Links to look up your own flight on Flightradar24. Nothing from Wingspot is sent there.
    @ViewBuilder private var lookup: some View {
        let flightPage = isOwn && shown.kind == "flown" ? shown.flightNumber.flatMap(Flightradar24.flight) : nil
        let aircraftPage = isOwn && shown.kind == "flown" ? shown.registration.flatMap { Registration($0) }.flatMap(Flightradar24.aircraft) : nil
        if flightPage != nil || aircraftPage != nil {
            Section {
                if let flightPage {
                    Link(destination: flightPage) { Label("Look up the flight on Flightradar24", systemImage: "arrow.up.right.square") }
                }
                if let aircraftPage {
                    Link(destination: aircraftPage) { Label("Look up the aircraft on Flightradar24", systemImage: "arrow.up.right.square") }
                }
            } footer: {
                Text("Opens Flightradar24 in your browser. Nothing from Wingspot is sent there.")
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

    private func commentsSection(_ store: CheckInCommentStore) -> some View {
        Section {
            if store.isLoading, !store.hasLoaded {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
            } else if let failure = store.failure, !store.hasLoaded {
                Text(failure.message).foregroundStyle(.secondary)
            } else if store.comments.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.largeTitle)
                        .foregroundStyle(.tint)
                    Text("No comments yet").font(.headline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .accessibilityElement(children: .combine)
            }
            ForEach(store.comments) { comment in
                let name = comment.displayName ?? comment.username
                HStack(alignment: .top, spacing: 12) {
                    AvatarView(id: comment.userID, name: name, size: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: name).font(.headline)
                            Spacer()
                            Text(comment.createdAt, format: .relative(presentation: .named))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Text(commentText(comment, extra: store.extras[comment.id])).font(.body)
                        commentActions(comment, store: store)
                    }
                }
                .padding(.vertical, 6)
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
        } header: {
            HStack {
                Text("Comments")
                if !store.comments.isEmpty { Text("\(store.comments.count)").foregroundStyle(.secondary) }
            }
            .font(.headline)
            .textCase(nil)
        }
    }

    /// The comment text, with each mentioned @name in the accent colour as a link to that person.
    private func commentText(_ comment: CheckInComment, extra: CommentExtra?) -> AttributedString {
        var result = AttributedString(comment.body)
        guard let mentions = extra?.mentions, !mentions.isEmpty else { return result }
        let byName = Dictionary(mentions.map { ($0.username, $0.id) }, uniquingKeysWith: { first, _ in first })
        for found in CommentText.mentionRanges(in: comment.body, usernames: Array(byName.keys)) {
            guard let range = Range(found.range, in: result), let id = byName[found.username],
                  let link = URL(string: "wingspot-person://\(id.uuidString.lowercased())") else { continue }
            result[range].link = link
            result[range].foregroundColor = .accentColor
            result[range].font = .body.weight(.semibold)
        }
        return result
    }

    /// Reply and salute under a comment.
    private func commentActions(_ comment: CheckInComment, store: CheckInCommentStore) -> some View {
        let extra = store.extras[comment.id] ?? CommentExtra()
        return HStack(spacing: 20) {
            if comment.userID != account.userID {
                Button("Reply") {
                    text = CommentText.replying(to: comment.username, in: text)
                    commentFocused = true
                }
                .accessibilityLabel(Text("Reply to \(comment.displayName ?? comment.username)"))
            }
            Button {
                Task { await store.toggleSalute(comment) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: extra.saluted ? "hands.clap.fill" : "hands.clap")
                    if extra.salutes > 0 { Text("\(extra.salutes)") }
                }
            }
            .accessibilityLabel(extra.saluted ? Text("Take back salute") : Text("Salute comment"))
            .accessibilityValue(Text("\(extra.salutes)"))
            Spacer(minLength: 0)
        }
        .font(.footnote.weight(.semibold))
        .buttonStyle(.borderless)
        .padding(.top, 2)
    }

    /// Friends that fit what is being typed after an "@", for the strip above the field.
    private var mentionSuggestions: [PersonTag] {
        guard let prefix = CommentText.activePrefix(in: text) else { return [] }
        return friends
            .filter { $0.id != account.userID }
            .filter { prefix.isEmpty || $0.username.lowercased().hasPrefix(prefix) || $0.name.lowercased().contains(prefix) }
            .prefix(10).map { $0 }
    }

    private func mentionStrip(_ people: [PersonTag]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(people) { person in
                    Button {
                        text = CommentText.completing(text, with: person.username)
                    } label: {
                        HStack(spacing: 6) {
                            AvatarView(id: person.id, name: person.name, size: 24)
                            Text(verbatim: person.name).font(.subheadline)
                        }
                        .padding(.vertical, 4)
                        .padding(.leading, 6)
                        .padding(.trailing, 12)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 8)
    }

    private func composer(_ store: CheckInCommentStore) -> some View {
        VStack(spacing: 0) {
            let people = mentionSuggestions
            if !people.isEmpty { mentionStrip(people) }
            composerField(store)
        }
        .background(.bar)
        .onChange(of: text) {
            guard !friendsLoaded, CommentText.activePrefix(in: text) != nil else { return }
            friendsLoaded = true
            Task { friends = await list.taggableFriends() }
        }
    }

    private func composerField(_ store: CheckInCommentStore) -> some View {
        let canSend = CheckInCommentStore.isSendable(text) && !store.isSending
        return HStack(alignment: .bottom, spacing: 10) {
            TextField("Write a comment…", text: $text, axis: .vertical)
                .lineLimit(1...5)
                .font(.body)
                .focused($commentFocused)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            Button {
                send(store)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(canSend ? Color.accentColor : Color.gray.opacity(0.35), in: Circle())
            }
            .accessibilityLabel("Send")
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Saves a copy of the friend's flight or visit on this device, linked to the original. It goes up with the next sync.
    private func addToLogbook() {
        let store = CheckInStore(context: modelContext)
        do {
            if shown.kind == "flown", let origin = shown.originID, let destination = shown.destinationID {
                let draft = FlownDraft(
                    origin: .init(airportID: origin, code: shown.originCode ?? "?"),
                    destination: .init(airportID: destination, code: shown.destinationCode ?? "?"),
                    distanceKm: shown.distanceKm, flightNumber: shown.flightNumber,
                    registration: shown.registration.flatMap { Registration($0) },
                    type: shown.typeICAO.map { .init(icaoCode: $0, name: shown.typeName ?? $0) }, sourceID: item.id
                )
                _ = try store.saveFlown(draft, ownerID: account.userID, at: shown.occurredAt)
            } else if shown.kind == "airport", let airport = shown.airportID {
                let draft = AirportDraft(airportID: airport, code: shown.airportCode ?? "?", context: .spotting, sourceID: item.id)
                _ = try store.saveAirport(draft, ownerID: account.userID, at: shown.occurredAt)
            } else {
                return
            }
            sync?.requestSync()
        } catch {
            problem = .unknown
        }
    }

    /// Opens the flight form for the way back: this flight's route the other way round, on the same day.
    private func prepareReturn() async {
        guard let database = referenceData.database, let from = shown.originID, let to = shown.destinationID,
              let origin = try? await database.airport(id: from), let destination = try? await database.airport(id: to)
        else {
            problem = .unknown
            return
        }
        returnStart = ReturnStart(
            origin: destination, destination: origin, date: min(shown.occurredAt, Date()),
            cabin: shown.cabin.flatMap(CabinClass.init(rawValue:)), tagged: tags.filter { $0.id != account.userID }
        )
    }

    private func send(_ store: CheckInCommentStore) {
        let draft = text
        Task {
            do {
                try await store.send(draft)
                text = ""
                commentFocused = false
            } catch {
                problem = (error as? AccountError) ?? .unknown
            }
        }
    }
}
