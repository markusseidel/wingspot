import Account
import Persistence
import SwiftData
import SwiftUI
import WingspotCore

/// Takes over a friend's flight or airport visit you are tagged on (#273): looks for the same flight among yours, asks what to do when
/// there is one ("Keep mine", "Replace the flight data"), and otherwise saves a copy on this phone, linked to the original.
@MainActor @Observable
final class CompanionFlow {
    /// The question shown when the friend's flight is one the person already has.
    struct Ask: Identifiable {
        let id = UUID()
        let item: FeedItem
        let match: MatchingFlight
    }

    var ask: Ask?
    var problem: AccountError?
    private(set) var isWorking = false

    /// "Add to my logbook". `mine` are the check-ins on this phone, for the fallback when the server can't be asked.
    func accept(_ item: FeedItem, feed: FeedStore, context: ModelContext, userID: UUID?, sync: CheckInSyncCoordinator?) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        if item.kind == "flown" {
            var matches = await feed.matches(for: item.id)
            if matches.isEmpty { matches = Self.localMatches(for: item, in: context, userID: userID) }
            if let best = matches.first {
                ask = Ask(item: item, match: best)
                return
            }
        }
        save(copyOf: item, feed: feed, context: context, userID: userID, sync: sync)
    }

    /// The person chose what to do with the flight they already have.
    func choose(_ choice: CompanionChoice, for ask: Ask, feed: FeedStore, context: ModelContext, userID: UUID?, sync: CheckInSyncCoordinator?) async {
        self.ask = nil
        isWorking = true
        defer { isWorking = false }
        let store = CheckInStore(context: context)
        do {
            switch choice {
            case .keepMine:
                guard try await feed.link(mine: ask.match.id, to: ask.item.id) else { problem = .unknown; return }
                _ = try store.setSource(id: ask.match.id, source: ask.item.id)
            case .replace:
                guard let facts = try await feed.replace(mine: ask.match.id, with: ask.item.id),
                      let origin = ask.item.originCode, let destination = ask.item.destinationCode else { problem = .unknown; return }
                _ = try store.replaceFlightData(
                    id: ask.match.id, flightNumber: facts.flightNumber,
                    origin: .init(airportID: facts.originID, code: origin), destination: .init(airportID: facts.destinationID, code: destination),
                    occurredAt: facts.occurredAt, registration: facts.registration,
                    type: facts.typeICAO.map { .init(icaoCode: $0, name: ask.item.typeName ?? $0) }, source: ask.item.id
                )
            }
            await feed.loadCompanionRequests()
        } catch {
            problem = (error as? AccountError) ?? .unknown
        }
    }

    /// Saves a copy of the friend's flight or visit on this phone, linked to the original. It goes up with the next sync.
    private func save(copyOf item: FeedItem, feed: FeedStore, context: ModelContext, userID: UUID?, sync: CheckInSyncCoordinator?) {
        let store = CheckInStore(context: context)
        do {
            if item.kind == "flown", let origin = item.originID, let destination = item.destinationID {
                let draft = FlownDraft(
                    origin: .init(airportID: origin, code: item.originCode ?? "?"),
                    destination: .init(airportID: destination, code: item.destinationCode ?? "?"),
                    distanceKm: item.distanceKm, flightNumber: item.flightNumber,
                    registration: item.registration.flatMap { Registration($0) },
                    type: item.typeICAO.map { .init(icaoCode: $0, name: item.typeName ?? $0) }, sourceID: item.id
                )
                _ = try store.saveFlown(draft, ownerID: userID, at: item.occurredAt)
            } else if item.kind == "airport", let airport = item.airportID {
                let draft = AirportDraft(airportID: airport, code: item.airportCode ?? "?", context: .spotting, sourceID: item.id)
                _ = try store.saveAirport(draft, ownerID: userID, at: item.occurredAt)
            } else {
                return
            }
            feed.requestAnswered(item.id)
            sync?.requestSync()
        } catch {
            problem = .unknown
        }
    }

    /// The flights on this phone with the same flight number on the same day, for when the server can't be asked.
    private static func localMatches(for item: FeedItem, in context: ModelContext, userID: UUID?) -> [MatchingFlight] {
        let number = KmlBatch.normalized(item.flightNumber)
        guard !number.isEmpty else { return [] }
        let mine = (try? context.fetch(FetchDescriptor<LocalCheckIn>(predicate: #Predicate { $0.kind == "flown" && $0.ownerID == userID }))) ?? []
        var found: [MatchingFlight] = []
        for flight in mine where KmlBatch.normalized(flight.flightNumber) == number && flight.sourceID == nil {
            guard Calendar.current.isDate(flight.occurredAt, inSameDayAs: item.occurredAt) else { continue }
            found.append(MatchingFlight(
                id: flight.id, reason: "number", secondsApart: Int(flight.occurredAt.timeIntervalSince(item.occurredAt)),
                flightNumber: flight.flightNumber, occurredAt: flight.occurredAt, originCode: flight.originCode, destinationCode: flight.destinationCode
            ))
        }
        return found
    }
}

/// The question "You already logged this flight": keep it, or replace its flight data with the friend's.
private struct CompanionAskModifier: ViewModifier {
    @Bindable var flow: CompanionFlow
    let onChoose: (CompanionChoice, CompanionFlow.Ask) -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                title, isPresented: Binding(get: { flow.ask != nil }, set: { if !$0 { flow.ask = nil } }), titleVisibility: .visible, presenting: flow.ask
            ) { ask in
                Button("Keep mine") { onChoose(.keepMine, ask) }
                Button("Replace the flight data") { onChoose(.replace, ask) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Keeping yours links the two flights. Replacing changes only the flight data: your photos, notes and comments stay.")
            }
            .alert("Couldn't add the flight", isPresented: Binding(get: { flow.problem != nil }, set: { if !$0 { flow.problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                if let problem = flow.problem { Text(problem.message) }
            }
    }

    private var title: String {
        guard let match = flow.ask?.match else { return "" }
        let number = match.flightNumber ?? [match.originCode, match.destinationCode].compactMap { $0 }.joined(separator: " → ")
        return String(localized: "You already logged \(number) on \(match.occurredAt.formatted(date: .abbreviated, time: .omitted)).")
    }
}

extension View {
    func companionAsk(_ flow: CompanionFlow, onChoose: @escaping (CompanionChoice, CompanionFlow.Ask) -> Void) -> some View {
        modifier(CompanionAskModifier(flow: flow, onChoose: onChoose))
    }
}
