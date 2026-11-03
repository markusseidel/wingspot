import Foundation

/// Flight data read from an IATA Bar Coded Boarding Pass (Resolution 792).
///
/// Passenger name and booking reference (PNR) are skipped while parsing and never exposed,
/// so they cannot be stored or uploaded by accident.
public struct BoardingPass: Equatable, Sendable {
    public struct Leg: Equatable, Sendable {
        /// IATA airport code, e.g. `FRA`.
        public let from: String
        public let to: String
        /// Operating carrier designator, e.g. `LH`.
        public let carrier: String
        /// Flight number without leading zeros, including an optional suffix, e.g. `400`, `32A`.
        public let flightNumber: String
        /// Julian day of the flight (1–366). The year is not encoded, see `flightDate(near:calendar:)`.
        public let dayOfYear: Int
        /// Booking class letter. Its cabin meaning is airline specific.
        public let compartmentCode: String
        /// Seat without leading zeros, e.g. `34K`. `nil` when no seat is assigned.
        public let seat: String?

        /// Resolves the flight date to the year that puts it closest to `reference` (usually the scan date).
        public func flightDate(near reference: Date, calendar: Calendar = .current) -> Date? {
            let year = calendar.component(.year, from: reference)
            return (year - 1...year + 1)
                .compactMap { Self.date(dayOfYear: dayOfYear, year: $0, calendar: calendar) }
                .min { abs($0.timeIntervalSince(reference)) < abs($1.timeIntervalSince(reference)) }
        }

        private static func date(dayOfYear: Int, year: Int, calendar: Calendar) -> Date? {
            guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
                  let days = calendar.range(of: .day, in: .year, for: start),
                  days.contains(dayOfYear)
            else { return nil }
            return calendar.date(byAdding: .day, value: dayOfYear - 1, to: start)
        }
    }

    /// BCBP version number from the conditional section, e.g. `6`. `nil` for mandatory-only barcodes.
    public let version: String?
    public let legs: [Leg]
}

public enum BCBPError: Error, Equatable, Sendable {
    case invalidFormatCode
    case invalidLegCount
    case truncated
    case invalidField(String)

    /// Stable identifier, shared with the Android app via `contracts/test-vectors/bcbp.json`.
    public var code: String {
        switch self {
        case .invalidFormatCode: "invalidFormatCode"
        case .invalidLegCount: "invalidLegCount"
        case .truncated: "truncated"
        case .invalidField: "invalidField"
        }
    }
}
