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
            if let registration = checkIn.registration {
                add(registration, title: registration, subtitle: checkIn.typeName, at: checkIn.occurredAt, to: &aircraft)
            }
            if let code = checkIn.typeICAO {
                add(code, title: code, subtitle: checkIn.typeName, at: checkIn.occurredAt, to: &types)
            }
            // A flight's airports don't count, as in the stats.
            if checkIn.kind != "flown", let code = checkIn.airportCode {
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
}
