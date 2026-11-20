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
    fun kilometresFlownAddsUpEachFlightFromItsAirports() {
        fun flight(origin: Long, destination: Long) =
            checkIn("flown", "2026-11-05T10:00:00Z").copy(originId = origin, destinationId = destination)
        val stats = CheckInStats.of(listOf(flight(3, 9), flight(3, 9), flight(3, 7)))
        // 3 is at 0,0 and 9 one degree of latitude north, about 111 km. Airport 7 is not known, so its flight is left out.
        val places = mapOf(3L to GeoCoordinate(0.0, 0.0), 9L to GeoCoordinate(1.0, 0.0))
        assertEquals(222, stats.kilometres { places[it] })
        assertEquals(0, stats.kilometres { null })
    }

    @Test
    fun recentTypesOfAFlightNumberComeNewestFirstEachOnce() {
        fun flight(number: String, type: String, at: String) = checkIn("flown", at, type = type).copy(flightNumber = number)
        val flights = listOf(
            flight("LH400", "B744", "2026-11-01T10:00:00Z"), flight("LH400", "A388", "2026-11-02T10:00:00Z"),
            flight("LH400", "B744", "2026-11-03T10:00:00Z"), flight("LH401", "A321", "2026-11-03T10:00:00Z"),
        )
        assertEquals(listOf("B744", "A388"), RecentTypes.forFlight(flights, " lh400 "))
        assertEquals(emptyList(), RecentTypes.forFlight(flights, ""))
        assertEquals(emptyList(), RecentTypes.forFlight(flights, "LH999"))
        assertEquals(listOf("A388", "B744"), RecentTypes.forFlight(flights, "LH400", excluding = flights[2].id))
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

class BadgesTakenBackTests {
    private val api = SocialApi(Rest("http://x/", "k", { "t" }), "http://x/storage/v1")
    private fun progress(level: Int) = api.parseProgress(
        """{"xp":0,"level":1,"xp_for_level":0,"xp_for_next_level":100,"hidden_remaining":0,"badges":[
        {"id":"logbook","name":{"en":"Logbook"},"category":"milestones","kind":"leveled","hidden":false,"levels":[10,25],"value":$level,"level":$level,
        "unlocked_at":"2026-11-05T20:31:20.920684+00:00"}]}""",
    )
    private val firstSeen = Instant.parse("2026-11-05T20:00:00Z").toEpochMilli()

    @Test
    fun aBadgeThatWentDownLowersWhatWasShownSoEarningItAgainIsCelebrated() {
        // Level 2 was shown. A delete took it down to level 1.
        val down = Celebrations.compute(progress(1), mapOf("logbook" to 2), firstSeen)
        assertEquals(mapOf("logbook" to 1), down.loweredAcks)
        assertTrue(down.celebrations.isEmpty())
        // Earning level 2 again: the stored acknowledgement is now 1, so it is celebrated from level 1.
        val again = Celebrations.compute(progress(2), mapOf("logbook" to 1), firstSeen)
        assertEquals(1, again.celebrations.single().previousLevel)
    }

    @Test
    fun aBadgeTheServerNoLongerListsCountsAsLevelZero() {
        val result = Celebrations.compute(progress(0).copy(badges = emptyList()), mapOf("logbook" to 1), firstSeen)
        assertEquals(mapOf("logbook" to 0), result.loweredAcks)
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
    fun tagsFriendsAndLeavingAreReadAndSent() = withServer { server, api, _ ->
        server.enqueue(ok("""[{"checkin_id":"c1","user_id":"u1","username":"anna","display_name":"Anna"},{"checkin_id":"c1","user_id":"u2","username":"max","display_name":null}]"""))
        val tags = api.tags(listOf("c1", "c2"))
        assertEquals(listOf("Anna", "max"), tags["c1"]!!.map { it.who })
        assertEquals(null, tags["c2"])
        val request = server.takeRequest()
        assertEquals("/rest/v1/rpc/get_checkin_tags", request.url.encodedPath)
        assertEquals("""{"ids":["c1","c2"]}""", request.body!!.utf8())

        server.enqueue(ok("""[{"id":"u1","username":"anna","display_name":"Anna"}]"""))
        assertEquals(listOf("u1"), api.taggableFriends().map { it.id })
        server.takeRequest()

        server.enqueue(ok("", 204))
        api.removeMyTag("c1")
        assertEquals("""{"checkin":"c1"}""", server.takeRequest().body!!.utf8())

        server.enqueue(ok("""[{"allow_tags":false}]"""))
        assertEquals(false, api.allowsTags("me"))
        server.takeRequest()
        server.enqueue(ok("", 204))
        api.setAllowsTags("me", true)
        val patch = server.takeRequest()
        assertEquals("PATCH", patch.method)
        assertEquals("""{"allow_tags":true}""", patch.body!!.utf8())
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

class RecentSuggestionsTests {
    private fun saved(kind: String, at: String, type: String? = null, airport: Long? = null, origin: Long? = null, destination: Long? = null) =
        LocalCheckIn(
            UUID.randomUUID(), kind, Instant.parse(at), null, type, airport, null, null, SyncState.SYNCED, null,
            originId = origin, destinationId = destination,
        )

    @Test
    fun recentTypesAndAirportsComeNewestFirstEachOnce() {
        val all = listOf(
            saved("spotted", "2026-11-01T10:00:00Z", "B744", airport = 7),
            saved("spotted", "2026-11-02T10:00:00Z", "A388", airport = 3),
            saved("flown", "2026-11-03T10:00:00Z", "B744", origin = 3, destination = 9),
        )
        assertEquals(listOf("B744", "A388"), RecentTypes.types(all))
        assertEquals(listOf("B744"), RecentTypes.types(all, limit = 1))
        // The flight's airports first (destination, origin), then the earlier sighting's.
        assertEquals(listOf(9L, 3L, 7L), RecentTypes.airportIds(all))
        assertEquals(listOf(9L, 3L), RecentTypes.airportIds(all, limit = 2))
    }
}
