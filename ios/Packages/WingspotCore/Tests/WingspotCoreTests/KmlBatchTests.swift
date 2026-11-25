import Foundation
import Testing
@testable import WingspotCore

private var calendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
}

@Test func aFlightTheLogbookHasIsMarked() {
    let result = KmlBatch.duplicates(
        in: [.init(flightNumber: "LH 400", day: day(2026, 8, 12)), .init(flightNumber: "LH401", day: day(2026, 8, 12))],
        existing: [.init(flightNumber: "LH400", day: day(2026, 8, 12, hour: 3))], calendar: calendar
    )
    #expect(result == [true, false])
}

@Test func theSameFlightTwiceInTheBatchIsMarkedTheSecondTime() {
    let result = KmlBatch.duplicates(
        in: [.init(flightNumber: "LH400", day: day(2026, 8, 12)), .init(flightNumber: "lh400", day: day(2026, 8, 12)), .init(flightNumber: "LH400", day: day(2026, 8, 13))],
        existing: [], calendar: calendar
    )
    #expect(result == [false, true, false])
}

@Test func theSameLinkIsTheSameFlight() {
    let result = KmlBatch.duplicates(
        in: [.init(flightNumber: nil, day: nil, link: "https://fr24/abc"), .init(flightNumber: "LH400", day: day(2026, 8, 12), link: "https://fr24/abc")],
        existing: [], calendar: calendar
    )
    #expect(result == [false, true])
}

@Test func anEntryWithoutANumberOrADayIsNeverMarkedByNumber() {
    let result = KmlBatch.duplicates(
        in: [.init(flightNumber: nil, day: day(2026, 8, 12)), .init(flightNumber: "LH400", day: nil)],
        existing: [.init(flightNumber: "LH400", day: day(2026, 8, 12))], calendar: calendar
    )
    #expect(result == [false, false])
}
