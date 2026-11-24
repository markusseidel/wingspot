import Foundation
import Testing
@testable import WingspotCore

private let english = Locale(identifier: "en_US")
private let german = Locale(identifier: "de_DE")
private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}
/// 22 November 2026, 12:00 UTC.
private let now = Date(timeIntervalSince1970: 1_795_348_800)

private func text(_ secondsAgo: TimeInterval, _ locale: Locale = english) -> String {
    FeedDate.text(for: now.addingTimeInterval(-secondsAgo), now: now, locale: locale, calendar: calendar)
}

@Test func recentTimesAreRelative() {
    #expect(text(5 * 60) == "5 minutes ago")
    #expect(text(3 * 3600) == "3 hours ago")
    #expect(text(3 * 24 * 3600) == "3 days ago")
}

@Test func relativeTextFollowsTheLanguage() {
    #expect(text(3 * 3600, german) == "vor 3 Stunden")
}

@Test func afterAWeekItIsAShortDateWithoutTheCurrentYear() {
    let nineDays = text(9 * 24 * 3600)
    #expect(nineDays == "Nov 13")
    #expect(!nineDays.contains("2026"))
    #expect(text(9 * 24 * 3600, german) == "13. Nov.")
}

@Test func anEarlierYearShowsTheYear() {
    // 15 September 2013
    let old = FeedDate.text(for: Date(timeIntervalSince1970: 1_379_246_400), now: now, locale: english, calendar: calendar)
    #expect(old == "Sep 15, 2013")
    let oldGerman = FeedDate.text(for: Date(timeIntervalSince1970: 1_379_246_400), now: now, locale: german, calendar: calendar)
    #expect(oldGerman == "15. Sept. 2013")
}

@Test func lastYearIsNotCalledLastYear() {
    // 29 June 2025: the old rule said "last year"
    let date = FeedDate.text(for: Date(timeIntervalSince1970: 1_751_198_400), now: now, locale: english, calendar: calendar)
    #expect(date == "Jun 29, 2025")
}

@Test func aTimeJustAheadIsStillRelative() {
    #expect(FeedDate.text(for: now.addingTimeInterval(3600), now: now, locale: english, calendar: calendar) == "in 1 hour")
}

@Test func aDayWithoutATimeSaysTheDayNotTheHours() {
    let english = Locale(identifier: "en_US")
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 21))!
    let noon = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 12))!
    #expect(FeedDate.text(for: noon, now: now, locale: english, calendar: calendar, timeKnown: false) == "yesterday")
    let threeDays = calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 12))!
    #expect(FeedDate.text(for: threeDays, now: now, locale: english, calendar: calendar, timeKnown: false) == "3 days ago")
}
