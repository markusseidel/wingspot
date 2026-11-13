package site.wingspot.core

import androidx.sqlite.execSQL
import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer

private val FRA = Place(3, "FRA")
private val JFK = Place(9, "JFK")

class AirportAndFlownStoreTests {
    private fun store() = CheckInStore.open(":memory:")

    @Test
    fun anAirportVisitCountsTheVisitsHere() = runBlocking {
        val s = store()
        assertEquals(1, s.saveAirport(AirportDraft(FRA)).visitsHere)
        assertEquals(2, s.saveAirport(AirportDraft(FRA, VisitContext.WORKING)).visitsHere)
        val newest = s.recent().first()
        assertEquals("airport", newest.kind)
        assertEquals("working", newest.visitContext)
        assertEquals("FRA", newest.title)
    }

    @Test
    fun aFlightIsSavedWithItsRouteAndAnAirportVisitForEachEnd() = runBlocking {
        val s = store()
        val first = s.saveFlown(FlownDraft(FRA, JFK, flightNumber = " lh 400 ", seat = " 12a ", cabin = CabinClass.BUSINESS))
        assertEquals("FRA → JFK", first.route)
        assertEquals(1, first.timesOnRoute)
        assertEquals(2, s.saveFlown(FlownDraft(FRA, JFK)).timesOnRoute)
        val flight = assertNotNull(s.find(first.id))
        assertEquals("LH400", flight.flightNumber)
        assertEquals("12A", flight.seat)
        assertEquals("business", flight.cabin)
        assertEquals(listOf("departing", "arriving", "departing", "arriving"), s.recent().filter { it.kind == "airport" }.reversed().map { it.visitContext })
    }

    @Test
    fun aFlightNeedsTwoDifferentAirports() = runBlocking {
        assertFailsWith<IllegalArgumentException> { store().saveFlown(FlownDraft(FRA, FRA)) }
        Unit
    }

    @Test
    fun editingAFlightKeepsTheRouteAndSendsItAgain() = runBlocking {
        val s = store()
        val id = s.saveFlown(FlownDraft(FRA, JFK)).id
        s.markSynced(listOf(id))
        assertTrue(s.updateFlown(id, Registration.parse("D-AIMA"), "A388", "lh400", CabinClass.ECONOMY, " 34k "))
        val flight = assertNotNull(s.find(id))
        assertEquals("D-AIMA", flight.registration)
        assertEquals("A388", flight.typeIcao)
        assertEquals("LH400", flight.flightNumber)
        assertEquals("34K", flight.seat)
        assertEquals(SyncState.PENDING, flight.syncState)
        assertEquals("FRA", flight.originCode)
        assertFalse(s.updateFlown(UUID.randomUUID(), null, null, null, null, null), "no such flight on this phone")
    }

    @Test
    fun deletingRemovesTheCheckInAndItsPhotos() = runBlocking {
        val s = store()
        val a = s.saveSpotted(SpottedDraft(registration = Registration.parse("D-AIMA")))
        val b = s.saveSpotted(SpottedDraft(registration = Registration.parse("D-AIMB")))
        assertNotNull(s.addPhoto(b.id, byteArrayOf(1), 10, 10))
        s.delete(b.id)
        s.delete(UUID.randomUUID())
        assertEquals(listOf(a.id), s.recent().map { it.id })
        assertEquals(0, s.photoCount(b.id))
    }

    @Test
    fun aCheckInTakesFourPhotesAtMost() = runBlocking {
        val s = store()
        val id = s.saveSpotted(SpottedDraft(typeIcao = "A320")).id
        repeat(4) { assertNotNull(s.addPhoto(id, byteArrayOf(1), 10, 10, Instant.now().plusMillis(it.toLong()))) }
        assertNull(s.addPhoto(id, byteArrayOf(1), 10, 10))
    }

    @Test
    fun anOldDatabaseGainsTheNewColumns() {
        val path = java.io.File.createTempFile("old", ".sqlite").also { it.delete() }.path
        val connection = androidx.sqlite.driver.bundled.BundledSQLiteDriver().open(path)
        connection.execSQL(
            """CREATE TABLE checkins (id TEXT PRIMARY KEY, kind TEXT NOT NULL, occurred_at INTEGER NOT NULL, registration TEXT,
               type_icao TEXT, airport_id INTEGER, latitude REAL, longitude REAL, sync_state TEXT NOT NULL DEFAULT 'pending', reject_code TEXT)""",
        )
        connection.execSQL("INSERT INTO checkins (id, kind, occurred_at, registration) VALUES ('${UUID.randomUUID()}', 'spotted', 1, 'D-AIMA')")
        connection.close()
        val s = CheckInStore.open(path)
        runBlocking {
            assertEquals("D-AIMA", s.recent().single().registration)
            assertEquals(1, s.saveFlown(FlownDraft(FRA, JFK)).timesOnRoute)
        }
    }
}

class PhotoCleanerTests {
    private fun segment(marker: Int, size: Int) = byteArrayOf(0xFF.toByte(), marker.toByte(), 0, (size + 2).toByte()) + ByteArray(size)

    @Test
    fun exifAndXmpAreCutOutAndTheRestStays() {
        val jfif = segment(0xE0, 14)
        val exif = segment(0xE1, 30)
        val comment = segment(0xFE, 5)
        val profile = segment(0xE2, 8)
        val picture = byteArrayOf(0xFF.toByte(), 0xDA.toByte(), 0, 2, 1, 2, 3, 0xFF.toByte(), 0xD9.toByte())
        val input = byteArrayOf(0xFF.toByte(), 0xD8.toByte()) + jfif + exif + comment + profile + picture
        val expected = byteArrayOf(0xFF.toByte(), 0xD8.toByte()) + jfif + profile + picture
        assertContentEquals(expected, PhotoCleaner.removeMetadata(input))
    }

    @Test
    fun somethingThatIsNotAJpegIsLeftAlone() {
        val text = "hello world".toByteArray()
        assertContentEquals(text, PhotoCleaner.removeMetadata(text))
    }
}

class PhotoAndDeleteSyncTests {
    private fun withOutbox(block: suspend (MockWebServer, CheckInStore, Outbox) -> Unit) {
        MockWebServer().use { server ->
            server.start()
            val store = CheckInStore.open(":memory:")
            val api = ApiClient(server.url("/functions").toString(), restUrl = server.url("/rest/v1").toString(), apiKey = "pub-key")
            runBlocking { block(server, store, Outbox(store, api) { "token" }) }
        }
    }

    private fun json(body: String, code: Int = 200) = MockResponse.Builder().code(code).body(body).build()

    @Test
    fun aPhotoGoesUpOnlyAfterItsCheckInIsStored() = withOutbox { server, store, outbox ->
        val id = store.saveSpotted(SpottedDraft(typeIcao = "A320")).id
        val photo = store.addPhoto(id, byteArrayOf(1, 2, 3), 10, 10)!!
        server.enqueue(json("""{"results":[{"id":"$id","status":"stored"}]}"""))
        server.enqueue(json("""{"id":"$photo","status":"stored"}"""))
        assertEquals(SyncOutcome.Done(2, 0), outbox.sync())
        server.takeRequest()
        val put = server.takeRequest()
        assertEquals("PUT", put.method)
        assertEquals("/functions/v1/checkins/$id/photos/$photo", put.url.encodedPath)
        assertEquals("image/jpeg", put.headers["Content-Type"])
        assertEquals(emptyList(), store.photosReadyToSend())
    }

    @Test
    fun aPhotoWaitsWhenTheServerDoesNotKnowTheCheckInYet() = withOutbox { server, store, outbox ->
        val id = store.saveSpotted(SpottedDraft(typeIcao = "A320")).id
        store.addPhoto(id, byteArrayOf(1), 10, 10)
        server.enqueue(json("""{"results":[{"id":"$id","status":"stored"}]}"""))
        server.enqueue(json("""{"code":"unknown_checkin","message":"x"}""", 404))
        assertEquals(SyncOutcome.RetryLater, outbox.sync())
        assertEquals(1, store.photosReadyToSend().size)
    }

    @Test
    fun aRefusedPhotoIsFinalAndAPhotoOfARejectedCheckInIsToo() = withOutbox { server, store, outbox ->
        val a = store.saveSpotted(SpottedDraft(typeIcao = "A320")).id
        val b = store.saveSpotted(SpottedDraft(typeIcao = "ZZZZ")).id
        val photoA = store.addPhoto(a, byteArrayOf(1), 10, 10)!!
        store.addPhoto(b, byteArrayOf(1), 10, 10)
        server.enqueue(json("""{"results":[{"id":"$a","status":"stored"},{"id":"$b","status":"rejected","code":"unknown_type"}]}"""))
        server.enqueue(json("""{"code":"too_many_photos","message":"x"}""", 409))
        assertEquals(SyncOutcome.Done(1, 2), outbox.sync())
        assertEquals(emptyList(), store.photosReadyToSend())
        assertEquals(photoA, photoA)
    }

    @Test
    fun deletingASyncedCheckInAsksTheServerFirst() = withOutbox { server, store, outbox ->
        val id = store.saveSpotted(SpottedDraft(typeIcao = "A320")).id
        store.markSynced(listOf(id))
        server.enqueue(json("", 204))
        assertTrue(outbox.delete(id))
        val request = server.takeRequest()
        assertEquals("/rest/v1/rpc/delete_checkin", request.url.encodedPath)
        assertEquals("pub-key", request.headers["apikey"])
        assertEquals("Bearer token", request.headers["Authorization"])
        assertEquals(id.toString(), Json.parseToJsonElement(request.body!!.utf8()).jsonObject["target"]!!.jsonPrimitive.content)
        assertNull(store.find(id))
    }

    @Test
    fun aFailedServerDeleteKeepsTheCheckInButANeverSentOneJustGoes() = withOutbox { server, store, outbox ->
        val sent = store.saveSpotted(SpottedDraft(typeIcao = "A320")).id
        store.markSynced(listOf(sent))
        val local = store.saveSpotted(SpottedDraft(typeIcao = "B738")).id
        server.enqueue(json("", 503))
        assertFalse(outbox.delete(sent))
        assertNotNull(store.find(sent))
        assertTrue(outbox.delete(local))
        assertNull(store.find(local))
        assertEquals(1, server.requestCount)
    }
}
