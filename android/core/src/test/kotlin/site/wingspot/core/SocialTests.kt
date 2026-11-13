package site.wingspot.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer

private const val ME = "00000000-0000-0000-0000-000000000001"
private const val OTHER = "00000000-0000-0000-0000-000000000002"
private const val CHECKIN = "00000000-0000-0000-0000-0000000000c1"

private fun feedRow(id: String = CHECKIN) =
    """{"id":"$id","user_id":"$OTHER","username":"anna","display_name":null,"kind":"flown","occurred_at":"2026-11-01T12:00:00.123456+00:00",
       "registration":null,"type_icao":"A388","type_name":"Airbus A380-800","airport_id":null,"airport_code":null,"origin_code":"FRA",
       "destination_code":"JFK","flight_number":"LH400","distance_km":6200,"salutes":2,"comments":1,"saluted":true,"something_new":1}"""

class SocialApiTests {
    private fun withApi(block: suspend (MockWebServer, SocialApi, MutableList<Boolean>) -> Unit) {
        MockWebServer().use { server ->
            server.start()
            val refreshes = mutableListOf<Boolean>()
            val rest = Rest(server.url("/").toString(), "pub-key", { force -> refreshes += force; if (force) "fresh" else "old" })
            runBlocking { block(server, SocialApi(rest, server.url("/storage/v1").toString()), refreshes) }
        }
    }

    private fun ok(body: String, code: Int = 200) = MockResponse.Builder().code(code).body(body).build()

    @Test
    fun theFeedIsReadAndThePageCursorGoesBackUnchanged() = withApi { server, api, _ ->
        server.enqueue(ok("[${feedRow()}]"))
        val items = api.feed(FeedCursor("2026-11-02T10:00:00.654321+00:00", "00000000-0000-0000-0000-0000000000aa"), 30)
        val item = items.single()
        assertEquals("FRA → JFK", item.title)
        assertEquals("anna", item.who)
        assertEquals("2026-11-01T12:00:00.123456+00:00", item.occurredAt)
        assertEquals(true, item.saluted)
        val request = server.takeRequest()
        assertEquals("/rest/v1/rpc/get_feed", request.url.encodedPath)
        assertEquals("Bearer old", request.headers["Authorization"])
        assertEquals("pub-key", request.headers["apikey"])
        val body = Rest(server.url("/").toString(), "k", { "t" }).json.parseToJsonElement(request.body!!.utf8()).jsonObject
        assertEquals("2026-11-02T10:00:00.654321+00:00", body["before_time"]!!.jsonPrimitive.content)
        assertEquals(30, body["page_size"]!!.jsonPrimitive.content.toInt())
    }

    @Test
    fun anExpiredTokenIsRefreshedOnce() = withApi { server, api, refreshes ->
        server.enqueue(ok("{}", 401))
        server.enqueue(ok("[]"))
        assertEquals(emptyList(), api.feed(null))
        assertEquals(listOf(false, true), refreshes)
        server.takeRequest()
        assertEquals("Bearer fresh", server.takeRequest().headers["Authorization"])
    }

    @Test
    fun aCheckInByIdIsNullWhenItCantBeSeen() = withApi { server, api, _ ->
        server.enqueue(ok("[]"))
        assertNull(api.checkIn(CHECKIN))
    }

    @Test
    fun salutingTwiceIsFineButOtherRefusalsAreNot() = withApi { server, api, _ ->
        server.enqueue(ok("""{"code":"23505","message":"duplicate"}""", 409))
        api.setSalute(true, CHECKIN, ME)
        server.enqueue(ok("""{"code":"42501","message":"no"}""", 403))
        val failure = assertFailsWith<ApiException.Failed> { api.setSalute(true, CHECKIN, ME) }
        assertEquals("42501", failure.code)
        server.takeRequest()
        server.takeRequest()
        server.enqueue(ok("", 204))
        api.setSalute(false, CHECKIN, ME)
        val delete = server.takeRequest()
        assertEquals("DELETE", delete.method)
        assertEquals("eq.$ME", delete.url.queryParameter("user_id"))
    }

    @Test
    fun commentsComeWithTheirAuthorAndTheWordFilterIsReported() = withApi { server, api, _ ->
        server.enqueue(ok("""[{"id":"c1","user_id":"$OTHER","body":"Nice!","created_at":"2026-11-01T12:00:00+00:00","profiles":{"username":"anna","display_name":"Anna K"}}]"""))
        assertEquals("Anna K", api.comments(CHECKIN).single().who)
        server.enqueue(ok("""{"code":"23514","message":"filter"}""", 400))
        assertEquals("23514", assertFailsWith<ApiException.Failed> { api.addComment("bad", CHECKIN, ME) }.code)
    }

    @Test
    fun photoLinksAreSignedAndJoinedToTheStorageAddress() = withApi { server, api, _ ->
        server.enqueue(ok("""[{"id":"p1","checkin_id":"$CHECKIN","storage_path":"u/c/p1.jpg","width":100,"height":50,"position":0}]"""))
        server.enqueue(ok("""[{"path":"u/c/p1.jpg","signedURL":"/object/sign/photos/u/c/p1.jpg?token=abc","error":null}]"""))
        val photo = api.photos(listOf(CHECKIN)).single()
        assertTrue(photo.url.endsWith("/storage/v1/object/sign/photos/u/c/p1.jpg?token=abc"), photo.url)
        assertEquals(emptyList(), api.photos(emptyList()))
    }

    @Test
    fun peopleAreSearchedAndFollowedAndUnfollowed() = withApi { server, api, _ ->
        server.enqueue(ok("""[{"id":"$OTHER","username":"anna","display_name":null,"is_private":true}]"""))
        val found = api.searchPeople("an a", ME).single()
        assertTrue(found.isPrivate)
        val search = server.takeRequest()
        assertEquals("ilike.*an a*", search.url.queryParameter("username"))
        server.enqueue(ok("", 201))
        api.follow(OTHER, ME)
        server.enqueue(ok("", 204))
        api.unfollow(OTHER, ME)
        server.takeRequest()
        assertEquals("DELETE", server.takeRequest().method)
    }

    @Test
    fun sharingIsReadAndSet() = withApi { server, api, _ ->
        server.enqueue(ok("""[{"id":"$ME","default_visibility":"friends"}]"""))
        assertEquals(SharingChoice.FRIENDS, api.sharing(ME))
        server.enqueue(ok("3"))
        assertEquals(3, api.setSharing(SharingChoice.EVERYONE, true))
    }
}

class UsernameTests {
    @Test
    fun theRuleMatchesTheDatabaseAndPlaceholdersAreRecognised() {
        assertEquals("spotter_1", Username.normalized(" Spotter_1 "))
        assertTrue(Username.isValid("spotter_1"))
        assertTrue(!Username.isValid("ab") && !Username.isValid("Has Space"))
        assertTrue(Username.isPlaceholder("user_" + "a".repeat(25)))
        assertTrue(!Username.isPlaceholder("user_abc"))
    }
}
