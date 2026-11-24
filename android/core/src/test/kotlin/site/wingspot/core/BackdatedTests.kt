package site.wingspot.core

import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.runBlocking

class BackdatedTests {
    private val berlin = ZoneId.of("Europe/Berlin")
    private val now = Instant.parse("2026-11-24T20:00:00Z")

    private fun store() = CheckInStore.open(":memory:")

    @Test
    fun nowIsNowAndTodayWithoutATimeIsNow() {
        assertEquals(Moment(now, true), WhenChoice.NOW.moment(now, berlin))
        assertEquals(Moment(now, true), WhenChoice(false, LocalDate.of(2026, 11, 24), null).moment(now, berlin))
    }

    @Test
    fun anotherDayWithoutATimeIsMiddayAndHasNoTime() {
        val moment = WhenChoice(false, LocalDate.of(2019, 8, 12), null).moment(now, berlin)
        assertEquals(Instant.parse("2019-08-12T10:00:00Z"), moment.at)
        assertFalse(moment.timeKnown)
    }

    @Test
    fun aTimeWinsAndNeverLiesInTheFuture() {
        val past = WhenChoice(false, LocalDate.of(2019, 8, 12), LocalTime.of(10, 30)).moment(now, berlin)
        assertEquals(Moment(Instant.parse("2019-08-12T08:30:00Z"), true), past)
        val future = WhenChoice(false, LocalDate.of(2026, 11, 24), LocalTime.of(23, 59)).moment(now, berlin)
        assertEquals(now, future.at)
    }

    @Test
    fun aPhotoSuggestionNeedsADateMoreThanADayAgo() {
        assertNull(WhenChoice.suggestion(now.minusSeconds(3600), now))
        assertNull(WhenChoice.suggestion(null, now))
        val old = now.minusSeconds(86_400L * 30)
        assertEquals(old, WhenChoice.suggestion(old, now))
        assertEquals(WhenChoice(false, LocalDate.of(2019, 8, 12), LocalTime.of(10, 30)), WhenChoice.usingPhoto(Instant.parse("2019-08-12T08:30:00Z"), berlin))
    }

    @Test
    fun theCaptureDateIsReadWithAndWithoutAnOffset() {
        assertEquals(Instant.parse("2019-08-12T08:30:05Z"), PhotoDates.parse("2019:08:12 10:30:05", null, berlin))
        assertEquals(Instant.parse("2019-08-12T15:30:05Z"), PhotoDates.parse("2019:08:12 10:30:05", "-05:00", berlin))
        assertNull(PhotoDates.parse("not a date", null, berlin))
        assertNull(PhotoDates.parse(null, null, berlin))
        assertNull(PhotoDates.parse("1970:01:01 00:00:00", null, berlin))
    }

    @Test
    fun aBackdatedFirstSightingIsAFirstTimeEvenIfSeenLaterAndKeepsItsDay() = runBlocking {
        val store = store()
        store.saveSpotted(SpottedDraft(registration = Registration.parse("D-AIMA")), now)
        val day = Instant.parse("2019-08-12T10:00:00Z")
        val result = store.saveSpotted(SpottedDraft(registration = Registration.parse("D-AIMA")), day, timeKnown = false)
        assertEquals(History.FirstTime, result.history)
        val saved = store.all().first { it.id == result.id }
        assertEquals(day, saved.occurredAt)
        assertFalse(saved.timeKnown)
    }

    @Test
    fun movingAVisitMovesItsSightingsByTheSameStep() = runBlocking {
        val store = store()
        val start = Instant.parse("2026-03-01T08:00:00Z")
        val visit = store.saveAirport(AirportDraft(place = Place(1L, "FRA")), start)
        store.saveSpotted(SpottedDraft(registration = Registration.parse("D-AIMB"), visitId = visit.id), start.plusSeconds(600))
        store.saveSpotted(SpottedDraft(registration = Registration.parse("D-AIMC")), start.plusSeconds(600))
        val moved = start.minusSeconds(86_400L * 2)
        store.updateVisit(visit.id, VisitContext.SPOTTING, occurredAt = moved, timeKnown = false)
        val all = store.all()
        assertEquals(moved, all.first { it.id == visit.id }.occurredAt)
        assertFalse(all.first { it.id == visit.id }.timeKnown)
        assertEquals(moved.plusSeconds(600), all.first { it.registration == "D-AIMB" }.occurredAt)
        assertEquals(start.plusSeconds(600), all.first { it.registration == "D-AIMC" }.occurredAt)
    }

    @Test
    fun editingASightingMovesItAndLeavesAnUnchangedOneAlone() = runBlocking {
        val store = store()
        val result = store.saveSpotted(SpottedDraft(registration = Registration.parse("D-AIMD")), now)
        store.updateSpotted(result.id, Registration.parse("D-AIMD"), null)
        assertEquals(now, store.all().first { it.id == result.id }.occurredAt)
        val day = Instant.parse("2020-05-05T10:00:00Z")
        store.updateSpotted(result.id, Registration.parse("D-AIMD"), null, occurredAt = day, timeKnown = false)
        val saved = store.all().first { it.id == result.id }
        assertEquals(day, saved.occurredAt)
        assertFalse(saved.timeKnown)
        store.updateSpotted(result.id, Registration.parse("D-AIMD"), null, occurredAt = day, timeKnown = true)
        assertTrue(store.all().first { it.id == result.id }.timeKnown)
    }
}
