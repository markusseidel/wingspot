package site.wingspot.core

import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue
import kotlinx.coroutines.runBlocking
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer

private fun checkIn(
    kind: String, at: String, registration: String? = null, type: String? = null, airport: Long? = null, code: String? = null,
    state: SyncState = SyncState.SYNCED,
) = LocalCheckIn(UUID.randomUUID(), kind, Instant.parse(at), registration, type, airport, null, null, state, null, airportCode = code)

class StatsTests {
    private val all = listOf(
        checkIn("spotted", "2026-11-01T10:00:00Z", "D-AIMA", "A388", 3, "FRA"),
        checkIn("spotted", "2026-11-02T10:00:00Z", "D-AIMA", "A388", 3, "FRA"),
        checkIn("spotted", "2026-11-03T10:00:00Z", null, "A320", 9, "JFK"),
        checkIn("airport", "2026-11-04T10:00:00Z", airport = 5, code = "MUC"),
        checkIn("flown", "2026-11-05T10:00:00Z", "D-AIXB", "B748"),
        checkIn("spotted", "2026-11-06T10:00:00Z", "D-REFUSED", "A320", 77, "XXX", SyncState.REJECTED),
    )

    @Test
    fun theNumbersLeaveOutWhatTheServerRefused() {
        val stats = CheckInStats.of(all)
        assertEquals(CheckInStats(checkIns = 5, sightings = 3, airportVisits = 1, flights = 1, aircraft = 2, types = 3, airports = 3), stats)
    }

    @Test
    fun collectionsAreSortedByCountThenByRecency() {
        val lists = Collections.of(all)
        assertEquals(listOf("D-AIMA", "D-AIXB"), lists.aircraft.map { it.title })
        assertEquals(2, lists.aircraft.first().count)
        assertEquals(listOf("A388", "B748", "A320"), lists.types.map { it.title })
        assertEquals(listOf("FRA", "JFK", "MUC").sorted(), lists.airports.map { it.title }.sorted())
        assertEquals("FRA", lists.airports.first().title)
    }

    @Test
    fun distancesAreShownInTheChosenUnit() {
        java.util.Locale.setDefault(java.util.Locale.US)
        assertEquals("6,200 km", DistanceUnit.KILOMETRES.format(6200))
        assertEquals(3348, DistanceUnit.NAUTICAL_MILES.value(6200))
        assertEquals(3853, DistanceUnit.MILES.value(6200))
    }
}

class BadgeTests {
    private val progressJson = """{"xp":120,"level":2,"xp_for_level":100,"xp_for_next_level":200,"hidden_remaining":3,
        "badges":[{"id":"logbook","name":{"en":"Logbook","de":"Logbuch"},"description":{"en":"Total check-ins"},"category":"milestones",
        "kind":"leveled","hidden":false,"levels":[10,25,50],"value":12,"level":1,"unlocked_at":"2026-11-05T20:31:20.920684+00:00"},
        {"id":"wheels_up","name":{"en":"Wheels Up"},"category":"milestones","hidden":false,"levels":[1],"value":1,"level":1,"unlocked_at":"2026-01-01T00:00:00+00:00"}]}"""

    private val api = SocialApi(Rest("http://x/", "k", { "t" }), "http://x/storage/v1")

    @Test
    fun theProgressAnswerIsReadAndNamesFollowTheLanguage() {
        val progress = api.parseProgress(progressJson)
        assertEquals(0.2f, progress.levelFraction)
        assertEquals(2, progress.earnedCount)
        val logbook = progress.badges[0]
        assertEquals("Logbuch", logbook.title(listOf("de-DE", "en")))
        assertEquals("Logbook", logbook.title(listOf("fr", "en")))
        assertEquals(25, logbook.nextTarget)
        assertTrue(progress.badges[1].isSingle && progress.badges[1].isComplete)
        assertEquals(Rank.CADET, Rank.of(4))
        assertEquals(Rank.STUDENT_PILOT, Rank.of(5))
        assertEquals(Rank.LEGEND, Rank.of(99))
        assertTrue(BadgeFilter.EARNED.matches(logbook) && BadgeFilter.IN_PROGRESS.matches(logbook) && !BadgeFilter.IN_PROGRESS.matches(progress.badges[1]))
    }

    @Test
    fun onlyNewUnlocksAreCelebratedAndOldOnesAreRecordedQuietly() {
        val progress = api.parseProgress(progressJson)
        val firstSeen = Instant.parse("2026-11-05T20:00:00Z").toEpochMilli()
        val result = Celebrations.compute(progress, emptyMap(), firstSeen)
        assertEquals(listOf("logbook"), result.celebrations.map { it.badge.id })
        assertEquals(0, result.celebrations.single().previousLevel)
        assertEquals(mapOf("wheels_up" to 1), result.newAcks)
        val again = Celebrations.compute(progress, mapOf("logbook" to 1, "wheels_up" to 1), firstSeen)
        assertTrue(again.celebrations.isEmpty() && again.newAcks.isEmpty())
    }
}

class AccountCallsTests {
    private fun withServer(block: suspend (MockWebServer, SocialApi, ApiClient) -> Unit) {
        MockWebServer().use { server ->
            server.start()
            val rest = Rest(server.url("/").toString(), "key", { "tok" })
            val api = ApiClient(server.url("/functions").toString())
            runBlocking { block(server, SocialApi(rest, server.url("/storage/v1").toString()), api) }
        }
    }

    private fun ok(body: String, code: Int = 200) = MockResponse.Builder().code(code).body(body).build()

    @Test
    fun privacyIsReadAndWritten() = withServer { server, api, _ ->
        server.enqueue(ok("""[{"is_private":true}]"""))
        server.enqueue(ok("""[{"id":"x","post_delay_minutes":360}]"""))
        assertEquals(SocialApi.Privacy(true, 360), api.privacy("me"))
        server.enqueue(ok("", 204))
        api.setPrivacy("me", SocialApi.Privacy(false, 60))
        server.takeRequest(); server.takeRequest()
        val patch = server.takeRequest()
        assertEquals("PATCH", patch.method)
        assertEquals("""{"is_private":false,"post_delay_minutes":60}""", patch.body!!.utf8())
    }

    @Test
    fun exportComesBackAsTheServerSentIt() = withServer { server, api, _ ->
        server.enqueue(ok("""{"profile":{}}"""))
        assertEquals("""{"profile":{}}""", api.exportMyData())
    }

    @Test
    fun deletingTheAccountCallsDeleteMeAndReportsFailures() = withServer { server, _, client ->
        server.enqueue(ok("", 204))
        client.deleteAccount("tok")
        val request = server.takeRequest()
        assertEquals("DELETE", request.method)
        assertEquals("/functions/v1/me", request.url.encodedPath)
        assertEquals("Bearer tok", request.headers["Authorization"])
        server.enqueue(ok("{}", 500))
        assertFailsWith<ApiException.Retry> { client.deleteAccount("tok") }
    }

    @Test
    fun everythingOnThePhoneCanBeRemoved() = runBlocking {
        val store = CheckInStore.open(":memory:")
        store.saveSpotted(SpottedDraft(typeIcao = "A320"))
        store.deleteEverything()
        assertEquals(emptyList(), store.all())
    }
}
