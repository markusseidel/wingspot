package site.wingspot.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.runBlocking
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer

class SightingSpotTests {
    @Test
    fun aSightingKeepsItsOwnPlaceAndAnEditCanChangeOrClearIt() = runBlocking {
        val s = CheckInStore.open(":memory:")
        val id = s.saveSpotted(SpottedDraft(registration = Registration.parse("D-AIMA"), spotId = 7, spotName = "North deck")).id
        assertEquals(7L, assertNotNull(s.find(id)).spotId)
        assertEquals("North deck", s.find(id)!!.spotName)
        // Not shown in the edit screen: the place stays.
        assertTrue(s.updateSpotted(id, Registration.parse("D-AIMA"), null))
        assertEquals(7L, s.find(id)!!.spotId)
        assertTrue(s.updateSpotted(id, Registration.parse("D-AIMA"), null, SpotChange.Set(9, "Hill")))
        assertEquals(9L, s.find(id)!!.spotId)
        assertEquals("Hill", s.find(id)!!.spotName)
        assertTrue(s.updateSpotted(id, Registration.parse("D-AIMA"), null, SpotChange.Clear))
        assertNull(s.find(id)!!.spotId)
        assertNull(s.find(id)!!.spotName)
        assertEquals(SyncState.PENDING, s.find(id)!!.syncState)
    }

    @Test
    fun aSightingAlwaysSendsItsPlaceSoNullCanClearIt() {
        MockWebServer().use { server ->
            server.start()
            val store = CheckInStore.open(":memory:")
            val api = ApiClient(server.url("/functions").toString(), restUrl = server.url("/rest/v1").toString(), apiKey = "pub-key")
            val outbox = Outbox(store, api) { "token" }
            runBlocking {
                val placed = store.saveSpotted(SpottedDraft(registration = Registration.parse("D-AIMA"), spotId = 5, spotName = "Deck")).id
                val bare = store.saveSpotted(SpottedDraft(registration = Registration.parse("D-AIMB"))).id
                val visit = store.saveAirport(AirportDraft(Place(3, "FRA"))).id
                server.enqueue(MockResponse.Builder().code(200).body("""{"results":[{"id":"$placed","status":"stored"},{"id":"$bare","status":"stored"},{"id":"$visit","status":"stored"}]}""").build())
                outbox.sync()
                val body = server.takeRequest().body!!.utf8()
                val items = kotlinx.serialization.json.Json.parseToJsonElement(body).let { (it as kotlinx.serialization.json.JsonObject)["checkins"] as kotlinx.serialization.json.JsonArray }
                fun item(id: java.util.UUID) = items.map { it as kotlinx.serialization.json.JsonObject }.first { it["id"].toString().contains(id.toString()) }
                assertEquals("5", item(placed)["spot_location_id"].toString())
                assertEquals("null", item(bare)["spot_location_id"].toString(), "a sighting without a place says so")
                assertTrue("spot_location_id" !in item(visit), "a visit without a place leaves the field out")
            }
        }
    }
}
