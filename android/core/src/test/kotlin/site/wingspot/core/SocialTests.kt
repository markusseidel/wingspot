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
        assertEquals("occurred", body["sort_by"]!!.jsonPrimitive.content, "an app that sends no sort gets the event order")
    }

    @Test
    fun theSalutesAndMentionsOfCommentsAreReadAndASaluteIsSent() = withApi { server, api, _ ->
        server.enqueue(ok("""[{"comment_id":"c1","salutes":2,"saluted":true,"mentions":[{"id":"$OTHER","username":"anna"}]},{"comment_id":"c2","salutes":0,"saluted":false,"mentions":[]}]"""))
        val extras = api.commentExtras(CHECKIN)
        assertEquals(2, extras.getValue("c1").salutes)
        assertEquals("anna", extras.getValue("c1").mentions.single().username)
        assertEquals("/rest/v1/rpc/get_comment_extras", server.takeRequest().url.encodedPath)
        server.enqueue(ok("null", 200))
        api.setCommentSalute("c2", true)
        val request = server.takeRequest()
        assertEquals("/rest/v1/rpc/set_comment_salute", request.url.encodedPath)
        val body = Rest(server.url("/").toString(), "k", { "t" }).json.parseToJsonElement(request.body!!.utf8()).jsonObject
        assertEquals("c2", body["p_comment"]!!.jsonPrimitive.content)
        assertEquals("true", body["p_on"]!!.jsonPrimitive.content)
    }

    @Test
    fun theFriendsWhoAddedACheckInToTheirLogbookAreRead() = withApi { server, api, _ ->
        server.enqueue(ok("""[{"user_id":"$OTHER","username":"anna","display_name":"Anna K"}]"""))
        val copies = api.checkInCopies(CHECKIN)
        assertEquals("Anna K", copies.single().who)
        assertEquals("/rest/v1/rpc/get_checkin_copies", server.takeRequest().url.encodedPath)
    }

    @Test
    fun aComparisonIsReadAndAHiddenProfileAnswersNull() = withApi { server, api, _ ->
        server.enqueue(ok("""{"me":{"flights":2,"distance_km":1200,"airports":3,"countries":3,"airlines":1,"types":2},
          "them":{"flights":2,"distance_km":1400,"airports":3,"countries":3,"airlines":2,"types":1},
          "airports":{"common":[{"key":1,"code":"ZA1","name":"Alpha"}],"mine":[],"theirs":[{"key":4,"code":"ZA4","name":"Delta"}]},
          "countries":{"common":[{"key":"DE","code":"DE"}],"mine":[],"theirs":[]},
          "airlines":{"common":[],"mine":[],"theirs":[]},"types":{"common":[],"mine":[{"key":"ZT2","code":"ZT2","name":"Test Two"}],"theirs":[]}}"""))
        val result = api.compare(OTHER)!!
        assertEquals(1200, result.me.distanceKm)
        assertEquals("Delta", result.airports.theirs.single().name)
        assertEquals("/rest/v1/rpc/compare_with", server.takeRequest().url.encodedPath)
        server.enqueue(ok("null"))
        assertNull(api.compare(OTHER))
    }

    @Test
    fun theLeaderboardIsReadAndTheSwitchIsSent() = withApi { server, api, _ ->
        server.enqueue(ok("""[{"user_id":"$OTHER","username":"anna","display_name":"Anna K","value":5400,"is_me":false},{"user_id":"$ME","username":"max","display_name":null,"value":500,"is_me":true}]"""))
        val rows = api.leaderboard("distance", "all")
        assertEquals(listOf("Anna K", "max"), rows.map { it.who })
        assertEquals(true, rows[1].isMe)
        val request = server.takeRequest()
        assertEquals("/rest/v1/rpc/get_leaderboard", request.url.encodedPath)
        val body = Rest(server.url("/").toString(), "k", { "t" }).json.parseToJsonElement(request.body!!.utf8()).jsonObject
        assertEquals("distance", body["p_metric"]!!.jsonPrimitive.content)
        server.enqueue(ok("""[{"show_on_leaderboard":true}]"""))
        assertEquals(true, api.showsOnLeaderboard(ME))
        server.takeRequest()
        server.enqueue(ok("", 204))
        api.setShowsOnLeaderboard(ME, true)
        assertEquals("PATCH", server.takeRequest().method)
    }

    @Test
    fun theInviteCodeFollowingByCodeAndSuggestionsAreRead() = withApi { server, api, _ ->
        server.enqueue(ok(""""ABCD2345""""))
        assertEquals("ABCD2345", api.myInviteCode())
        assertEquals("/rest/v1/rpc/get_my_invite_code", server.takeRequest().url.encodedPath)
        server.enqueue(ok("""[{"id":"$OTHER","username":"anna","display_name":"Anna K"}]"""))
        assertEquals("Anna K", api.followByCode("ABCD2345")!!.who)
        assertEquals("/rest/v1/rpc/follow_by_code", server.takeRequest().url.encodedPath)
        server.enqueue(ok("[]"))
        assertNull(api.inviteOwner("ABCD2345"))
        server.takeRequest()
        server.enqueue(ok("""[{"user_id":"$OTHER","username":"anna","display_name":null,"reason":"tagged","mutual":0}]"""))
        assertEquals("tagged", api.suggestions().single().reason)
    }

    @Test
    fun theInboxIsReadPagedByTimeAndMarkedRead() = withApi { server, api, _ ->
        server.enqueue(ok("""[{"id":"i1","kind":"salute","actor_id":"$OTHER","username":"anna","display_name":null,"checkin_id":"$CHECKIN",
            "subject":"FRA → JFK","snippet":null,"created_at":"2026-11-21T10:00:00.5+00:00","is_read":false}]"""))
        val row = api.activity("2026-11-22T10:00:00+00:00", 10).single()
        assertEquals("anna", row.who)
        assertEquals("FRA → JFK", row.subject)
        assertEquals(false, row.isRead)
        val request = server.takeRequest()
        assertEquals("/rest/v1/rpc/get_notifications", request.url.encodedPath)
        val body = Rest(server.url("/").toString(), "k", { "t" }).json.parseToJsonElement(request.body!!.utf8()).jsonObject
        assertEquals("2026-11-22T10:00:00+00:00", body["before"]!!.jsonPrimitive.content)
        assertEquals(10, body["lim"]!!.jsonPrimitive.content.toInt())

        server.enqueue(ok("7"))
        assertEquals(7, api.unreadActivityCount())
        assertEquals("/rest/v1/rpc/unread_notification_count", server.takeRequest().url.encodedPath)
        server.enqueue(ok("null"))
        api.markActivityRead()
        assertEquals("/rest/v1/rpc/mark_notifications_read", server.takeRequest().url.encodedPath)
        server.enqueue(ok("null"))
        api.markActivityRead("n-1")
        val one = server.takeRequest()
        assertEquals("/rest/v1/rpc/mark_notification_read", one.url.encodedPath)
        assertEquals("n-1", Rest(server.url("/").toString(), "k", { "t" }).json.parseToJsonElement(one.body!!.utf8()).jsonObject["p_id"]!!.jsonPrimitive.content)
    }

    @Test
    fun spottingLocationsAreReadForAnAirportAndOnePlaceAndASession() = withApi { server, api, _ ->
        server.enqueue(ok("""[{"id":7,"name":"North fence","latitude":50.1,"longitude":8.5,"description":null,"status":"pending","mine":true,"sessions":0}]"""))
        val places = api.spotLocations(5)
        assertEquals("North fence", places.single().name)
        assertEquals(true, places.single().isPending)
        val request = server.takeRequest()
        assertEquals("/rest/v1/rpc/spotting_locations_at", request.url.encodedPath)
        assertEquals(5, Rest(server.url("/").toString(), "k", { "t" }).json.parseToJsonElement(request.body!!.utf8()).jsonObject["p_airport"]!!.jsonPrimitive.content.toInt())

        server.enqueue(ok("null"))
        assertEquals(null, api.spotDetail(9))
        server.takeRequest()
        server.enqueue(ok("""{"id":7,"airport_id":5,"airport":"Frankfurt","iata":"FRA","name":"North fence","latitude":50.1,"longitude":8.5,"description":"View","best_time":"Morning","facing":null,"tips":null,"legal_notes":null,"photo_path":null,"status":"approved","mine":false,"sessions":3,"aircraft":12,"my_sessions":1}"""))
        val detail = api.spotDetail(7)!!
        assertEquals(12, detail.aircraft)
        assertEquals("Morning", detail.bestTime)
        server.takeRequest()

        server.enqueue(ok("""[{"id":"a1","occurred_at":"2026-03-01T08:10:00+00:00","registration":"D-AAAA","type_icao":null,"user_id":"u"}]"""))
        assertEquals("D-AAAA", api.visitSightings("v1").single().registration)
        server.takeRequest()
        server.enqueue(ok("null"))
        assertEquals(null, api.checkInSpot("c1"))
        server.takeRequest()
        server.enqueue(ok("""{"visit_id":"v1","spot_id":7,"spot_name":"North fence","sightings":2}"""))
        assertEquals(2, api.checkInSpot("v1")!!.sightings)
    }

    @Test
    fun theFeedCanBeSortedByCheckInTimeAndPagesByThatTime() = withApi { server, api, _ ->
        server.enqueue(ok("[" + feedRow().replace("\"something_new\":1", "\"cursor_time\":\"2026-11-03T09:00:00+00:00\"") + "]"))
        val item = api.feed(null, 30, FeedSort.CREATED).single()
        assertEquals("2026-11-03T09:00:00+00:00", item.cursorTime)
        val body = Rest(server.url("/").toString(), "k", { "t" }).json.parseToJsonElement(server.takeRequest().body!!.utf8()).jsonObject
        assertEquals("created", body["sort_by"]!!.jsonPrimitive.content)
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
        assertEquals("followers", SharingChoice.FOLLOWERS.wire)
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

class ExploreApiTests {
    private fun withApi(block: suspend (MockWebServer, SocialApi) -> Unit) {
        MockWebServer().use { server ->
            server.start()
            runBlocking { block(server, SocialApi(Rest(server.url("/").toString(), "k", { "t" }), "http://x")) }
        }
    }

    private fun ok(body: String) = MockResponse.Builder().code(200).body(body).build()

    @Test
    fun airportAndTypePagesSendTheirKeyAlongWithTheCursor() = withApi { server, api ->
        server.enqueue(ok("[]"))
        api.airportCheckIns(3, FeedCursor("2026-11-01T00:00:00+00:00", "id1"), 10)
        val airport = Rest("http://x", "k", { "t" }).json.parseToJsonElement(server.takeRequest().body!!.utf8()).jsonObject
        assertEquals("3", airport["airport"]!!.jsonPrimitive.content)
        assertEquals("id1", airport["before_id"]!!.jsonPrimitive.content)
        server.enqueue(ok("[]"))
        api.typeCheckIns("A388", null)
        val type = server.takeRequest()
        assertEquals("/rest/v1/rpc/get_type_checkins", type.url.encodedPath)
        assertEquals("A388", Rest("http://x", "k", { "t" }).json.parseToJsonElement(type.body!!.utf8()).jsonObject["type_code"]!!.jsonPrimitive.content)
        server.enqueue(ok("[]"))
        api.registrationCheckIns("D-AIMA", null)
        assertEquals("/rest/v1/rpc/get_registration_checkins", server.takeRequest().url.encodedPath)
    }

    @Test
    fun activityAndBusyAirportsAreRead() = withApi { server, api ->
        server.enqueue(ok("""[{"checkins_30d":12,"aircraft_30d":5,"top_spotters":[{"user_id":"u1","username":"anna","display_name":null,"checkins":7}]}]"""))
        val activity = api.airportActivity(3)!!
        assertEquals(12, activity.checkIns)
        assertEquals(5, activity.other)
        assertEquals("anna", activity.topSpotters.single().who)
        server.enqueue(ok("""[{"checkins_30d":0,"airports_30d":0,"top_spotters":null}]"""))
        assertEquals(emptyList(), api.typeActivity("A388")!!.topSpotters)
        server.enqueue(ok("""[{"airport_id":3,"airport_code":"FRA","airport_name":"Frankfurt","city":"Frankfurt","checkins":40,"people":9}]"""))
        assertEquals("FRA", api.activeAirports().single().code)
    }
}

class AlertTests {
    private fun withApi(block: suspend (MockWebServer, SocialApi) -> Unit) {
        MockWebServer().use { server ->
            server.start()
            runBlocking { block(server, SocialApi(Rest(server.url("/").toString(), "k", { "t" }), "http://x")) }
        }
    }

    private fun ok(body: String, code: Int = 200) = MockResponse.Builder().code(code).body(body).build()

    @Test
    fun prefsAreReadWithEverythingOnByDefault() = withApi { server, api ->
        server.enqueue(ok("[]"))
        assertEquals(SocialApi.NotificationPrefs(), api.notificationPrefs(ME))
        server.enqueue(ok("""[{"new_followers":true,"salutes":false,"comments":true,"followed_checkins":false,"tagged":false}]"""))
        assertEquals(SocialApi.NotificationPrefs(salutes = false, followedCheckins = false, tagged = false), api.notificationPrefs(ME))
        server.enqueue(ok("", 204))
        api.setNotificationPrefs(ME, SocialApi.NotificationPrefs(comments = false))
        server.takeRequest(); server.takeRequest()
        val patch = server.takeRequest()
        assertEquals("PATCH", patch.method)
        assertTrue(patch.body!!.utf8().contains(""""comments":false"""))
    }

    @Test
    fun aRuleIsSavedOrRemovedWhenEverythingIsOff() = withApi { server, api ->
        server.enqueue(ok("", 201))
        api.saveAlertRule(ME, SocialApi.AlertRule(OTHER, spotted = true))
        val save = server.takeRequest()
        assertEquals("watcher,target", save.url.queryParameter("on_conflict"))
        assertEquals("resolution=merge-duplicates,return=minimal", save.headers["Prefer"])
        server.enqueue(ok("", 204))
        api.saveAlertRule(ME, SocialApi.AlertRule(OTHER))
        assertEquals("DELETE", server.takeRequest().method)
        server.enqueue(ok("""[{"target":"$OTHER","spotted":true,"flown":false,"airport":true,"profiles":{"username":"anna","display_name":null}}]"""))
        val rule = api.alertRules(ME).single()
        assertEquals("anna", rule.who)
        assertTrue(rule.isOn)
    }

    @Test
    fun aDeviceIsRegisteredAsAndroidAndRemoved() = withApi { server, api ->
        server.enqueue(ok("{}"))
        api.registerDevice("dev1", "0.1.0", "fcm-token", "15", "de")
        val body = Rest("http://x", "k", { "t" }).json.parseToJsonElement(server.takeRequest().body!!.utf8()).jsonObject
        assertEquals("android", body["device_platform"]!!.jsonPrimitive.content)
        assertEquals("fcm-token", body["device_push_token"]!!.jsonPrimitive.content)
        server.enqueue(ok("", 204))
        api.removeDevice("dev1")
        assertEquals("/rest/v1/devices", server.takeRequest().url.encodedPath)
    }
}
