package site.wingspot.core

import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlinx.coroutines.runBlocking

class SimpleEditTests {
    private fun store() = CheckInStore.open(":memory:")
    private val frankfurt = Place(3, "FRA")

    @Test
    fun aSightingsAircraftIsCorrectedAndSentAgain() = runBlocking {
        val s = store()
        val id = s.saveSpotted(SpottedDraft(registration = Registration.parse("D-AIMA"))).id
        s.markSynced(listOf(id))
        assertTrue(s.updateSpotted(id, Registration.parse("D-AIMB"), "a388"))
        val sighting = assertNotNull(s.find(id))
        assertEquals("D-AIMB", sighting.registration)
        assertEquals("A388", sighting.typeIcao)
        assertEquals(SyncState.PENDING, sighting.syncState)
        assertFalse(s.updateSpotted(id, null, null), "needs a registration or a type")
        assertFalse(s.updateSpotted(UUID.randomUUID(), Registration.parse("D-AIMB"), null), "no such sighting on this phone")
    }

    @Test
    fun theReasonForAVisitIsCorrectedAndSentAgain() = runBlocking {
        val s = store()
        val id = s.saveAirport(AirportDraft(frankfurt, VisitContext.SPOTTING)).id
        s.markSynced(listOf(id))
        assertTrue(s.updateVisit(id, VisitContext.MUSEUM))
        val visit = assertNotNull(s.find(id))
        assertEquals("museum", visit.visitContext)
        assertEquals(SyncState.PENDING, visit.syncState)
        assertFalse(s.updateVisit(UUID.randomUUID(), VisitContext.WORKING), "no such visit on this phone")
    }
}
