import Foundation

/// Importing several KML files at once (#236): which of them are flights the person already has, or that the same batch has twice.
public enum KmlBatch {
    /// A flight as the batch sees it.
    public struct Entry: Sendable {
        public var flightNumber: String?
        public var day: Date?
        /// The link to the flight in the file: the same link twice is the same flight.
        public var link: String?

        public init(flightNumber: String?, day: Date?, link: String? = nil) {
            self.flightNumber = flightNumber
            self.day = day
            self.link = link
        }
    }

    /// A flight check-in the person already has.
    public struct Existing: Sendable {
        public var flightNumber: String?
        public var day: Date

        public init(flightNumber: String?, day: Date) {
            self.flightNumber = flightNumber
            self.day = day
        }
    }

    /// The flight number the way it is stored: upper case, no spaces. Empty when there is none.
    public static func normalized(_ number: String?) -> String {
        (number ?? "").filter { !$0.isWhitespace }.uppercased()
    }

    /// For each entry, whether it is a flight that is already there: a check-in with the same flight number on the same day, or an
    /// earlier entry of the batch with the same link, or the same number on the same day. An entry without a flight number or a day is
    /// never a duplicate of anything but its own link.
    public static func duplicates(in entries: [Entry], existing: [Existing], calendar: Calendar = .current) -> [Bool] {
        var seenKeys = Set<String>()
        var seenLinks = Set<String>()
        let have = Set(existing.compactMap { flight -> String? in
            let number = normalized(flight.flightNumber)
            return number.isEmpty ? nil : key(number, flight.day, calendar)
        })
        return entries.map { entry in
            var duplicate = false
            if let link = entry.link, !link.isEmpty, !seenLinks.insert(link).inserted { duplicate = true }
            let number = normalized(entry.flightNumber)
            if !number.isEmpty, let day = entry.day {
                let k = key(number, day, calendar)
                if have.contains(k) || !seenKeys.insert(k).inserted { duplicate = true }
            }
            return duplicate
        }
    }

    private static func key(_ number: String, _ day: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return "\(number)|\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}
