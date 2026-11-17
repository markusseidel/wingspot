package site.wingspot.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer

private const val ID = "00000000-0000-0000-0000-0000000000c1"

class CheckInVisibilityTests {
    private fun withApi(block: suspend (MockWebServer, SocialApi) -> Unit) {
        MockWebServer().use { server ->
            server.start()
            runBlocking { block(server, SocialApi(Rest(server.url("/").toString(), "k", { "t" }), "http://x")) }
        }
    }

    private fun ok(body: String) = MockResponse.Builder().code(200).body(body).build()

    @Test
    fun theLevelAndWhetherItWasSetByHandAreRead() = withApi { server, api ->
        server.enqueue(ok("""[{"visibility":"followers","is_custom":true}]"""))
        assertEquals(SharingChoice.FOLLOWERS to true, api.checkInVisibility(ID))
        val request = server.takeRequest()
        assertEquals("/rest/v1/rpc/get_checkin_visibility", request.url.encodedPath)
        server.enqueue(ok("[]"))
        assertNull(api.checkInVisibility(ID))
    }

    @Test
    fun aLevelIsSentByItsWireNameAndNullGoesBackToTheAccount() = withApi { server, api ->
        server.enqueue(ok("\"friends\""))
        assertEquals(SharingChoice.FRIENDS, api.setCheckInVisibility(ID, SharingChoice.FRIENDS))
        val sent = Rest("http://x", "k", { "t" }).json.parseToJsonElement(server.takeRequest().body!!.utf8()).jsonObject
        assertEquals(ID, sent["target"]!!.jsonPrimitive.content)
        assertEquals("friends", sent["new_visibility"]!!.jsonPrimitive.content)
        server.enqueue(ok("\"public\""))
        assertEquals(SharingChoice.EVERYONE, api.setCheckInVisibility(ID, null))
        val back = server.takeRequest().body!!.utf8()
        assertEquals("""{"target":"$ID","new_visibility":null}""", back)
        server.enqueue(ok("null"))
        assertNull(api.setCheckInVisibility(ID, SharingChoice.ONLY_ME))
    }
}
