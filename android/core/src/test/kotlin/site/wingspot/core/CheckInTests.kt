package site.wingspot.core

import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer

private fun reg(text: String) = Registration.parse(text)!!

class Uuid7Tests {
    @Test
    fun hasTheVersionAndVariantBitsAndSortsByTime() {
        val early = Uuid7.generate(1_700_000_000_000)
        val late = Uuid7.generate(1_700_000_001_000)
        assertEquals(7, early.version())
        assertEquals(2, early.variant())
        assertTrue(early.toString() < late.toString(), "the earlier id sorts first")
        assertTrue(early.toString().startsWith("018bcfe5-6800"), early.toString())
        assertTrue(Uuid7.generate() != Uuid7.generate())
    }
}

class CheckInStoreTests {
    private fun store() = CheckInStore.open(":memory:")

    @Test
    fun aCheckInNeedsAnAircraft() = runBlocking {
        val s = store()
        assertFailsWith<IllegalArgumentException> { s.saveSpotted(SpottedDraft()) }
        assertFailsWith<IllegalArgumentException> { s.saveSpotted(SpottedDraft(typeIcao = "A320", latitude = 1.0)) }
    }

    @Test
    fun theFirstTimeAndTheNextTimes() = runBlocking {
        val s = store()
        val t0 = Instant.parse("2026-11-01T10:00:00Z")
        val first = s.saveSpotted(SpottedDraft(registration = reg("daima")), t0)
        assertEquals("D-AIMA", first.subject)
        assertEquals(History.FirstTime, first.history)
        val second = s.saveSpotted(SpottedDraft(registration = reg("D-AIMA")), t0.plusSeconds(3600))
        assertEquals(History.SeenBefore(2, t0), second.history)
        val third = s.saveSpotted(SpottedDraft(registration = reg("D-AIMA")), t0.plusSeconds(7200))
        assertEquals(History.SeenBefore(3, t0.plusSeconds(3600)), third.history)
        assertEquals(History.FirstTime, s.saveSpotted(SpottedDraft(typeIcao = "a320"), t0).history)
        assertEquals("A320", s.recent().first { it.registration == null }.typeIcao)
    }

    @Test
    fun pendingRowsComeOldestFirstAndStatesStick() = runBlocking {
        val s = store()
        val t0 = Instant.parse("2026-11-01T10:00:00Z")
        val a = s.saveSpotted(SpottedDraft(registration = reg("D-AIMA")), t0)
        val b = s.saveSpotted(SpottedDraft(typeIcao = "B738", airportId = 7, latitude = 50.0, longitude = 8.0), t0.plusSeconds(60))
        assertEquals(listOf(a.id, b.id), s.pending().map { it.id })
        s.markSynced(listOf(a.id))
        s.markRejected(b.id, "unknown_airport")
        assertEquals(emptyList(), s.pending())
        val all = s.recent()
        assertEquals(listOf(b.id, a.id), all.map { it.id }, "newest first")
        assertEquals(SyncState.REJECTED, all[0].syncState)
        assertEquals("unknown_airport", all[0].rejectCode)
        assertEquals(7L, all[0].airportId)
        assertEquals(SyncState.SYNCED, all[1].syncState)
        assertNull(all[1].airportId)
    }
}

class OutboxTests {
    private fun withOutbox(block: suspend (MockWebServer, CheckInStore, Outbox, MutableList<Boolean>) -> Unit) {
        MockWebServer().use { server ->
            server.start()
            val store = CheckInStore.open(":memory:")
            val refreshes = mutableListOf<Boolean>()
            val outbox = Outbox(store, ApiClient(server.url("/functions").toString()), { force ->
                refreshes += force
                if (force) "fresh-token" else "old-token"
            })
            runBlocking { block(server, store, outbox, refreshes) }
        }
    }

    private fun answer(vararg results: Pair<UUID, String>, codes: Map<UUID, String> = emptyMap()) = MockResponse.Builder().code(200).body(
        """{"results":[${results.joinToString(",") { (id, status) -> """{"id":"$id","status":"$status"${codes[id]?.let { ""","code":"$it"""" } ?: ""}}""" }}]}""",
    ).build()

    @Test
    fun storedItemsAreMarkedAndTheRequestMatchesTheContract() = withOutbox { server, store, outbox, _ ->
        val t0 = Instant.parse("2026-11-01T10:00:00Z")
        val a = store.saveSpotted(SpottedDraft(registration = reg("D-AIMA"), airportId = 3, latitude = 50.1, longitude = 8.5), t0)
        val b = store.saveSpotted(SpottedDraft(typeIcao = "A320"), t0.plusSeconds(1))
        server.enqueue(answer(a.id to "stored", b.id to "stored"))
        assertEquals(SyncOutcome.Done(2, 0), outbox.sync())
        assertEquals(emptyList(), store.pending())

        val request = server.takeRequest()
        assertEquals("/functions/v1/checkins", request.url.encodedPath)
        assertEquals("Bearer old-token", request.headers["Authorization"])
        val items = Json.parseToJsonElement(request.body!!.utf8()).jsonObject["checkins"]!!.jsonArray.map { it.jsonObject }
        assertEquals(a.id.toString(), items[0]["id"]!!.jsonPrimitive.content)
        assertEquals("spotted", items[0]["kind"]!!.jsonPrimitive.content)
        assertEquals("2026-11-01T10:00:00Z", items[0]["occurred_at"]!!.jsonPrimitive.content)
        assertEquals("D-AIMA", items[0]["registration"]!!.jsonPrimitive.content)
        assertEquals(3, items[0]["airport_id"]!!.jsonPrimitive.content.toInt())
        assertEquals(50.1, items[0]["latitude"]!!.jsonPrimitive.content.toDouble())
        assertEquals("A320", items[1]["type_icao"]!!.jsonPrimitive.content)
        assertTrue("registration" !in items[1] && "latitude" !in items[1] && "visibility" !in items[0])
    }

    @Test
    fun aFlightWithATypeTheServerDoesNotKnowIsStoredWithoutIt() = withOutbox { server, store, outbox, _ ->
        val flight = store.saveFlown(FlownDraft(Place(3, "LIS"), Place(9, "MXP"), flightNumber = "TP832", typeIcao = "A21N"))
        val sent = store.pending().filter { it.kind == "flown" }.single().id
        server.enqueue(answer(*store.pending().map { it.id to (if (it.id == sent) "rejected" else "stored") }.toTypedArray(), codes = mapOf(sent to "unknown_type")))
        server.enqueue(answer(sent to "stored"))
        assertEquals(SyncOutcome.Done(3, 0), outbox.sync())
        server.takeRequest()
        val retry = Json.parseToJsonElement(server.takeRequest().body!!.utf8()).jsonObject["checkins"]!!.jsonArray.single().jsonObject
        assertTrue("type_icao" !in retry)
        assertEquals("TP832", retry["flight_number"]!!.jsonPrimitive.content)
        assertEquals("A21N", store.all().first { it.id == sent }.typeIcao, "the type stays on the phone")
    }

    @Test
    fun aRejectedItemIsFinalAndTheOthersAreNotBlocked() = withOutbox { server, store, outbox, _ ->
        val a = store.saveSpotted(SpottedDraft(registration = reg("D-AIMA")))
        val b = store.saveSpotted(SpottedDraft(typeIcao = "ZZZZ"))
        server.enqueue(answer(a.id to "stored", b.id to "rejected", codes = mapOf(b.id to "unknown_type")))
        assertEquals(SyncOutcome.Done(1, 1), outbox.sync())
        assertEquals("unknown_type", store.recent().first { it.id == b.id }.rejectCode)
        assertEquals(SyncOutcome.Done(0, 0), outbox.sync(), "nothing left, so no second request")
        assertEquals(1, server.requestCount)
    }

    @Test
    fun aServerErrorOrNoNetworkLeavesEverythingPending() = withOutbox { server, store, outbox, _ ->
        val a = store.saveSpotted(SpottedDraft(registration = reg("D-AIMA")))
        server.enqueue(MockResponse.Builder().code(503).body("busy").build())
        assertEquals(SyncOutcome.RetryLater, outbox.sync())
        assertEquals(listOf(a.id), store.pending().map { it.id })
        server.enqueue(answer(a.id to "stored"))
        assertEquals(SyncOutcome.Done(1, 0), outbox.sync(), "the retry sends the same id, which the server answers idempotently")
        server.close()
        store.saveSpotted(SpottedDraft(typeIcao = "B738"))
        assertEquals(SyncOutcome.RetryLater, outbox.sync(), "no connection")
        assertEquals(1, store.pending().size)
    }

    @Test
    fun anExpiredTokenIsRefreshedOnceAndTheUploadRetried() = withOutbox { server, store, outbox, refreshes ->
        val a = store.saveSpotted(SpottedDraft(registration = reg("D-AIMA")))
        server.enqueue(MockResponse.Builder().code(401).body("{}").build())
        server.enqueue(answer(a.id to "stored"))
        assertEquals(SyncOutcome.Done(1, 0), outbox.sync())
        assertEquals(listOf(false, true), refreshes)
        assertEquals("Bearer old-token", server.takeRequest().headers["Authorization"])
        assertEquals("Bearer fresh-token", server.takeRequest().headers["Authorization"])
    }

    @Test
    fun withoutASessionNothingIsSentAndAStillRefusedTokenMeansSignedOut() {
        MockWebServer().use { server ->
            server.start()
            val store = CheckInStore.open(":memory:")
            runBlocking { store.saveSpotted(SpottedDraft(registration = reg("D-AIMA"))) }
            val signedOut = Outbox(store, ApiClient(server.url("/").toString()), { null })
            assertEquals(SyncOutcome.SignedOut, runBlocking { signedOut.sync() })
            assertEquals(0, server.requestCount)
            server.enqueue(MockResponse.Builder().code(401).body("{}").build())
            server.enqueue(MockResponse.Builder().code(401).body("{}").build())
            val refused = Outbox(store, ApiClient(server.url("/").toString()), { "t" })
            assertEquals(SyncOutcome.SignedOut, runBlocking { refused.sync() })
            assertEquals(1, store.let { runBlocking { it.pending() } }.size)
        }
    }

    @Test
    fun aTokenThatCantBeRefreshedOfflineMeansRetryLater() {
        MockWebServer().use { server ->
            server.start()
            val store = CheckInStore.open(":memory:")
            runBlocking { store.saveSpotted(SpottedDraft(registration = reg("D-AIMA"))) }
            val outbox = Outbox(store, ApiClient(server.url("/").toString()), { throw ApiException.Retry })
            assertEquals(SyncOutcome.RetryLater, runBlocking { outbox.sync() })
            assertEquals(0, server.requestCount)
        }
    }

    @Test
    fun moreThanFiftyGoInBatches() = withOutbox { server, store, outbox, _ ->
        val t0 = Instant.parse("2026-11-01T10:00:00Z")
        val ids = (0 until 120).map { i -> store.saveSpotted(SpottedDraft(typeIcao = "A320"), t0.plusSeconds(i.toLong())).id }
        ids.chunked(50).forEach { chunk -> server.enqueue(answer(*chunk.map { it to "stored" }.toTypedArray())) }
        assertEquals(SyncOutcome.Done(120, 0), outbox.sync())
        val sizes = (0 until 3).map { Json.parseToJsonElement(server.takeRequest().body!!.utf8()).jsonObject["checkins"]!!.jsonArray.size }
        assertEquals(listOf(50, 50, 20), sizes)
    }

    @Test
    fun anAnswerThatSettlesNothingDoesNotLoopForever() = withOutbox { server, store, outbox, _ ->
        val a = store.saveSpotted(SpottedDraft(registration = reg("D-AIMA")))
        server.enqueue(answer(a.id to "queued"))
        assertEquals(SyncOutcome.RetryLater, outbox.sync())
        assertEquals(1, server.requestCount)
    }
}

class RefreshTests {
    @Test
    fun theRefreshTokenIsTradedForANewSession() {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(
                MockResponse.Builder().code(200).body(
                    """{"access_token":"a2","refresh_token":"r2","expires_in":3600,"user":{"id":"u1","email":"a@b.c"}}""",
                ).build(),
            )
            val session = runBlocking { SupabaseAuth(server.url("/").toString(), "key").refresh("r1") }
            assertEquals("a2", session.accessToken)
            val request = server.takeRequest()
            assertEquals("refresh_token", request.url.queryParameter("grant_type"))
            assertEquals("r1", Json.parseToJsonElement(request.body!!.utf8()).jsonObject["refresh_token"]!!.jsonPrimitive.content)
        }
    }
}

class Flightradar24Tests {
    @Test
    fun linksMatchTheIphoneApp() {
        assertEquals("https://www.flightradar24.com/data/flights/lh400", Flightradar24.flight("LH 400"))
        assertNull(Flightradar24.flight(" - "))
        assertEquals("https://www.flightradar24.com/data/aircraft/d-aima", Flightradar24.aircraft("D-AIMA"))
    }
}
