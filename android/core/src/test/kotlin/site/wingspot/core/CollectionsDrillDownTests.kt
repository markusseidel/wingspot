package site.wingspot.core

import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlinx.coroutines.runBlocking

private val FRA_PLACE = Place(3, "FRA")
private val DUS_PLACE = Place(7, "DUS")
private val JFK_PLACE = Place(9, "JFK")
private val DAY0 = Instant.parse("2026-01-01T12:00:00Z")
private fun day(n: Long) = DAY0.plusSeconds(n * 86_400)

class CollectionsDrillDownTests {
    private fun store() = CheckInStore.open(":memory:")

    /** Sightings, an airport visit, a flight (with the visits it creates) and a refused check-in. */
    private suspend fun fixture(s: CheckInStore): List<LocalCheckIn> {
        s.saveSpotted(SpottedDraft(registration = Registration.parse("D-AIMA"), typeIcao = "A388", airportId = 3, airportCode = "FRA"), day(1))
        s.saveSpotted(SpottedDraft(registration = Registration.parse("D-AIMA"), typeIcao = "A388", airportId = 3, airportCode = "FRA"), day(3))
        s.saveSpotted(SpottedDraft(registration = Registration.parse("D-AIMB"), typeIcao = "B744", airportId = 7, airportCode = "DUS"), day(2))
        s.saveAirport(AirportDraft(DUS_PLACE), day(4))
        s.saveFlown(FlownDraft(FRA_PLACE, JFK_PLACE, registration = Registration.parse("D-AIMB"), typeIcao = "B744"), day(5))
        val refused = s.saveSpotted(SpottedDraft(registration = Registration.parse("D-AIMA"), typeIcao = "A388", airportId = 3, airportCode = "FRA"), day(6))
        s.markRejected(refused.id, "invalid")
        return s.recent(100)
    }

    @Test
    fun theListOfAnEntryAlwaysMatchesItsCount() = runBlocking {
        val all = fixture(store())
        val lists = Collections.of(all)
        assertTrue(lists.aircraft.isNotEmpty() && lists.types.isNotEmpty() && lists.airports.isNotEmpty())
        for (e in lists.aircraft) assertEquals(e.count, Collections.checkIns(CollectionKind.AIRCRAFT, e.id, all).size)
        for (e in lists.types) assertEquals(e.count, Collections.checkIns(CollectionKind.TYPE, e.id, all).size)
        for (e in lists.airports) assertEquals(e.count, Collections.checkIns(CollectionKind.AIRPORT, e.id, all).size)
    }

    @Test
    fun anAirportListHasTheVisitsAFlightCreatedAndNoRefusedCheckIns() = runBlocking {
        val all = fixture(store())
        val fra = Collections.checkIns(CollectionKind.AIRPORT, "FRA", all)
        // Two sightings and the departure visit of the flight; the refused sighting does not count, the flight has no airport.
        assertEquals(3, fra.size)
        assertTrue(fra.none { it.kind == "flown" })
        assertTrue(fra.any { it.kind == "airport" && it.flightId != null })
        assertEquals(2, Collections.checkIns(CollectionKind.AIRCRAFT, "D-AIMA", all).size)
        assertTrue(Collections.checkIns(CollectionKind.AIRCRAFT, "D-AIMB", all).any { it.kind == "flown" })
    }

    @Test
    fun theFlightsTabListsFlightsOnly() = runBlocking {
        val flights = Collections.flights(fixture(store()))
        assertEquals(1, flights.size)
        assertEquals("FRA", flights.first().originCode)
    }

    @Test
    fun theListsFollowTheChosenDateAndDirection() {
        fun checkIn(n: Long, savedDay: Long) = LocalCheckIn(
            java.util.UUID.randomUUID(), "spotted", day(n), "D-AIMA", "A388", null, null, null, SyncState.SYNCED, null, savedAt = day(savedDay),
        )
        val early = checkIn(1, 30)
        val late = checkIn(3, 20)
        val both = listOf(early, late)
        assertEquals(listOf(late, early), Collections.ordered(both, CollectionDateKind.FLIGHT, ascending = false))
        assertEquals(listOf(early, late), Collections.ordered(both, CollectionDateKind.FLIGHT, ascending = true))
        assertEquals(listOf(early, late), Collections.ordered(both, CollectionDateKind.CHECK_IN, ascending = false))
        assertEquals(listOf(late, early), Collections.ordered(both, CollectionDateKind.CHECK_IN, ascending = true))
    }

    @Test
    fun theCheckInDateFallsBackToTheUploadAndThenTheFlightDate() = runBlocking {
        val s = store()
        s.saveSpotted(SpottedDraft(registration = Registration.parse("D-AIMA"), typeIcao = "A388"), day(1))
        val fresh = s.recent().first()
        // A new check-in has the time it was saved
        assertNotNull(fresh.savedAt)
        assertEquals(fresh.savedAt, fresh.enteredAt)
        // Older ones, or ones restored from the server, have none
        val old = fresh.copy(savedAt = null, syncedAt = null)
        assertEquals(day(1), old.enteredAt)
        assertEquals(day(9), old.copy(syncedAt = day(9)).enteredAt)
    }
}
