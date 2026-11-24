import Foundation

/// The date on a feed entry, one rule for both apps (docs/FEED-ENTRY-SPEC.md): relative for the last 7 days
/// ("3 hours ago", "yesterday"), after that a short date with the month abbreviated. The year is left out when it is
/// the current year, so a backdated flight shows its real date and not "13 years ago".
public enum FeedDate {
    /// `timeKnown` is `false` for an entry with only a day: within a week it then says "yesterday" or "3 days ago", never "2 hours ago".
    public static func text(for date: Date, now: Date = Date(), locale: Locale = .current, calendar: Calendar = .current, timeKnown: Bool = true) -> String {
        var calendar = calendar
        calendar.locale = locale
        if abs(now.timeIntervalSince(date)) < 7 * 24 * 3600 {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            formatter.dateTimeStyle = .named
            formatter.unitsStyle = .full
            if !timeKnown {
                let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
                return formatter.localizedString(from: DateComponents(day: -days))
            }
            return formatter.localizedString(for: date, relativeTo: now)
        }
        let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .day().month(.abbreviated)
        if !sameYear { style = style.year() }
        return date.formatted(style)
    }
}
