import Foundation
import SwiftData
import Testing
import WingspotCore
@testable import Persistence

@MainActor
@Suite struct BackdatedTests {
    private func store() throws -> (CheckInStore, ModelContext) {
        let container = try ModelContainer(for: LocalCheckIn.self, LocalPhoto.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        return (CheckInStore(context: context), context)
    }

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }

    @Test func nowIsNowAndTodayWithoutATimeIsNow() {
        let now = Date()
        #expect(WhenChoice.now.moment(now: now).date == now)
        #expect(WhenChoice.now.moment(now: now).timeKnown)
        let today = WhenChoice(isNow: false, date: now.addingTimeInterval(-3600), hasTime: false).moment(now: now, calendar: calendar)
        #expect(today.date == now && today.timeKnown)
    }

    @Test func anotherDayWithoutATimeIsMiddayAndHasNoTime() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 21))!
        let day = calendar.date(from: DateComponents(year: 2019, month: 8, day: 12, hour: 3))!
        let moment = WhenChoice(isNow: false, date: day, hasTime: false).moment(now: now, calendar: calendar)
        #expect(moment.date == calendar.date(from: DateComponents(year: 2019, month: 8, day: 12, hour: 12)))
        #expect(!moment.timeKnown)
    }

    @Test func aTimeWinsAndNeverLiesInTheFuture() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 21))!
        let past = calendar.date(from: DateComponents(year: 2019, month: 8, day: 12, hour: 10, minute: 30))!
        let moment = WhenChoice(isNow: false, date: past, hasTime: true).moment(now: now, calendar: calendar)
        #expect(moment.date == past && moment.timeKnown)
        let future = WhenChoice(isNow: false, date: now.addingTimeInterval(7200), hasTime: true).moment(now: now, calendar: calendar)
        #expect(future.date == now)
    }

    @Test func aPhotoSuggestionNeedsADateMoreThanADayAgo() {
        let now = Date()
        #expect(WhenChoice.suggestion(from: now.addingTimeInterval(-3600), now: now) == nil)
        #expect(WhenChoice.suggestion(from: nil, now: now) == nil)
        let old = now.addingTimeInterval(-86_400 * 30)
        #expect(WhenChoice.suggestion(from: old, now: now) == old)
        #expect(WhenChoice.usingPhoto(at: old) == WhenChoice(isNow: false, date: old, hasTime: true))
    }

    @Test func theCaptureDateIsReadWithAndWithoutAnOffset() {
        let berlin = TimeZone(identifier: "Europe/Berlin")!
        let plain = PhotoPreparer.parseCaptureDate("2019:08:12 10:30:05", timeZone: berlin)
        #expect(plain == ISO8601DateFormatter().date(from: "2019-08-12T08:30:05Z"))
        let offset = PhotoPreparer.parseCaptureDate("2019:08:12 10:30:05", offset: "-05:00", timeZone: berlin)
        #expect(offset == ISO8601DateFormatter().date(from: "2019-08-12T15:30:05Z"))
        #expect(PhotoPreparer.parseCaptureDate("not a date") == nil)
        #expect(PhotoPreparer.parseCaptureDate("1970:01:01 00:00:00", timeZone: berlin) == nil)
    }

    @Test func aBackdatedFirstSightingIsAFirstTimeEvenIfSeenLaterAndKeepsItsDay() throws {
        let (store, context) = try store()
        _ = try store.saveSpotted(SpottedDraft(registration: Registration("D-AIMA")))
        let day = ISO8601DateFormatter().date(from: "2019-08-12T12:00:00Z")!
        let result = try store.saveSpotted(SpottedDraft(registration: Registration("D-AIMA")), at: day, timeKnown: false)
        #expect(result.history == .firstTime)
        let saved = try context.fetch(FetchDescriptor<LocalCheckIn>()).first { $0.id == result.id }
        #expect(saved?.occurredAt == day)
        #expect(saved?.timeKnown == false)
    }

    @Test func movingAVisitMovesItsSightingsByTheSameStep() throws {
        let (store, context) = try store()
        let start = ISO8601DateFormatter().date(from: "2026-03-01T08:00:00Z")!
        let visit = try store.saveAirport(AirportDraft(airportID: 1, code: "FRA"), at: start)
        _ = try store.saveSpotted(
            SpottedDraft(registration: Registration("D-AIMB"), visitID: visit.id),
            at: start.addingTimeInterval(600)
        )
        _ = try store.saveSpotted(SpottedDraft(registration: Registration("D-AIMC")), at: start.addingTimeInterval(600))
        let moved = start.addingTimeInterval(-86_400 * 2)
        _ = try store.updateVisit(id: visit.id, reason: .spotting, occurredAt: moved, timeKnown: false)
        let all = try context.fetch(FetchDescriptor<LocalCheckIn>())
        #expect(all.first { $0.id == visit.id }?.occurredAt == moved)
        #expect(all.first { $0.id == visit.id }?.timeKnown == false)
        #expect(all.first { $0.registration == "D-AIMB" }?.occurredAt == moved.addingTimeInterval(600))
        #expect(all.first { $0.registration == "D-AIMC" }?.occurredAt == start.addingTimeInterval(600))
    }

    @Test func editingASightingMovesItAndLeavesAnUnchangedOneAlone() throws {
        let (store, context) = try store()
        let result = try store.saveSpotted(SpottedDraft(registration: Registration("D-AIMD")))
        let original = try context.fetch(FetchDescriptor<LocalCheckIn>()).first { $0.id == result.id }!.occurredAt
        _ = try store.updateSpotted(id: result.id, registration: Registration("D-AIMD"), type: nil)
        #expect(try context.fetch(FetchDescriptor<LocalCheckIn>()).first { $0.id == result.id }?.occurredAt == original)
        let day = ISO8601DateFormatter().date(from: "2020-05-05T12:00:00Z")!
        _ = try store.updateSpotted(id: result.id, registration: Registration("D-AIMD"), type: nil, occurredAt: day, timeKnown: false)
        let saved = try context.fetch(FetchDescriptor<LocalCheckIn>()).first { $0.id == result.id }
        #expect(saved?.occurredAt == day && saved?.timeKnown == false)
    }
}
