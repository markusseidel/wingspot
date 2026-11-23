import Foundation

/// The lists behind the stats: what has been seen, how often and when last. Worked out from the check-ins
/// on this device, with the same rules as `CheckInStats`.
public struct CheckInCollections: Equatable, Sendable {
    public struct Entry: Equatable, Sendable, Identifiable {
        public var id: String
        /// A registration, a type code or an airport code.
        public var title: String
        /// The type name for an aircraft or a type.
        public var subtitle: String?
        public var count: Int
        public var lastSeen: Date
    }

    public var aircraft: [Entry] = []
    public var types: [Entry] = []
    public var airports: [Entry] = []

    public init() {}

    /// Each list is sorted by the number of check-ins, then by the most recent first.
    public init(_ all: [LocalCheckIn], userID: UUID?) {
        var aircraft: [String: Entry] = [:]
        var types: [String: Entry] = [:]
        var airports: [String: Entry] = [:]

        func add(_ key: String, title: String, subtitle: String?, at date: Date, to list: inout [String: Entry]) {
            if var entry = list[key] {
                entry.count += 1
                if date > entry.lastSeen { entry.lastSeen = date }
                if entry.subtitle == nil { entry.subtitle = subtitle }
                list[key] = entry
            } else {
                list[key] = Entry(id: key, title: title, subtitle: subtitle, count: 1, lastSeen: date)
            }
        }

        for checkIn in CheckInStats.counted(all, userID: userID) {
            let keys = Self.keys(of: checkIn)
            if let registration = keys.aircraft {
                add(registration, title: registration, subtitle: checkIn.typeName, at: checkIn.occurredAt, to: &aircraft)
            }
            if let code = keys.type {
                add(code, title: code, subtitle: checkIn.typeName, at: checkIn.occurredAt, to: &types)
            }
            if let code = keys.airport {
                add(code, title: code, subtitle: nil, at: checkIn.occurredAt, to: &airports)
            }
        }
        let order: (Entry, Entry) -> Bool = {
            ($0.count, $0.lastSeen, $1.title) > ($1.count, $1.lastSeen, $0.title)
        }
        self.aircraft = aircraft.values.sorted(by: order)
        self.types = types.values.sorted(by: order)
        self.airports = airports.values.sorted(by: order)
    }

    /// Which entries a check-in belongs to. The counts above and `checkIns(of:key:in:userID:)` both use this, so the number
    /// of listed check-ins always matches the count of the entry.
    private static func keys(of checkIn: LocalCheckIn) -> (aircraft: String?, type: String?, airport: String?) {
        // A flight has no airport of its own. Its two airports are check-ins of their own.
        (checkIn.registration, checkIn.typeICAO, checkIn.kind != "flown" ? checkIn.airportCode : nil)
    }

    public enum Kind: Sendable { case aircraft, type, airport }

    /// The check-ins behind one entry of a list: all that count towards it, in no particular order (see `ordered`).
    public static func checkIns(of kind: Kind, key: String, in all: [LocalCheckIn], userID: UUID?) -> [LocalCheckIn] {
        CheckInStats.counted(all, userID: userID).filter { checkIn in
            let keys = keys(of: checkIn)
            switch kind {
            case .aircraft: return keys.aircraft == key
            case .type: return keys.type == key
            case .airport: return keys.airport == key
            }
        }
    }

    /// All flights, for the flights tab.
    public static func flights(in all: [LocalCheckIn], userID: UUID?) -> [LocalCheckIn] {
        CheckInStats.counted(all, userID: userID).filter { $0.kind == "flown" }
    }

    /// Which date a list is sorted by: the date of the flight or sighting, or the check-in date (`enteredAt`).
    public enum DateKind: String, Sendable, CaseIterable { case flight, checkIn }

    /// Sorted by the chosen date, then the other one and the id, so the order never flickers between equal dates.
    public static func ordered(_ list: [LocalCheckIn], by kind: DateKind, ascending: Bool) -> [LocalCheckIn] {
        func date(_ checkIn: LocalCheckIn) -> Date { kind == .flight ? checkIn.occurredAt : checkIn.enteredAt }
        func other(_ checkIn: LocalCheckIn) -> Date { kind == .flight ? checkIn.enteredAt : checkIn.occurredAt }
        return list.sorted { a, b in
            let left = (date(a), other(a), a.id.uuidString), right = (date(b), other(b), b.id.uuidString)
            return ascending ? left < right : left > right
        }
    }
}
