import Foundation

/// What the "When" row of a sighting or an airport check-in has chosen (#312): now, a day, or a day with a time.
public struct WhenChoice: Equatable, Sendable {
    /// "Now": the date and time are the moment of saving.
    public var isNow: Bool
    /// The chosen day (and the time, when `hasTime`).
    public var date: Date
    /// Whether the time of day was set. Without it only the day counts and no time is shown later.
    public var hasTime: Bool

    public static let now = WhenChoice(isNow: true, date: Date(), hasTime: false)

    public init(isNow: Bool = true, date: Date = Date(), hasTime: Bool = false) {
        self.isNow = isNow
        self.date = date
        self.hasTime = hasTime
    }

    /// The moment to store, and whether its time is known. A day without a time is stored as midday (so it stays on that day in
    /// any time zone) and marked as having no time; today without a time is just now. A time later than now is cut back to now.
    public func moment(now: Date = Date(), calendar: Calendar = .current) -> (date: Date, timeKnown: Bool) {
        if isNow { return (now, true) }
        if hasTime { return (min(date, now), true) }
        if calendar.isDate(date, inSameDayAs: now) { return (now, true) }
        return (FlightDay.moment(of: date, now: now, calendar: calendar), false)
    }

    /// A date for the picker, never after now.
    public static func limit(_ date: Date, now: Date = Date()) -> Date { min(date, now) }

    /// A suggestion from a photo's capture date: only when it is more than a day before now.
    public static func suggestion(from takenAt: Date?, now: Date = Date()) -> Date? {
        guard let takenAt, takenAt < now.addingTimeInterval(-86_400) else { return nil }
        return takenAt
    }

    /// The choice that a tap on the suggestion sets: the photo's day and time.
    public static func usingPhoto(at takenAt: Date) -> WhenChoice { WhenChoice(isNow: false, date: takenAt, hasTime: true) }

    /// The choice an edit screen starts with: the check-in's own date, with its time when known.
    public static func existing(_ date: Date, timeKnown: Bool) -> WhenChoice { WhenChoice(isNow: false, date: date, hasTime: timeKnown) }
}
