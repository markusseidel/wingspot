package site.wingspot.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlinx.coroutines.runBlocking
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer

private const val ROWS = """[
  {"id":"a1","title_en":"Small list","body_en":"The type list stays small.","title_de":"Kleine Liste","body_de":"Die Typenliste bleibt klein.","created_at":"2026-11-16T10:00:00+00:00","expires_at":null,"something_new":1},
  {"id":"a2","title_en":"English only","body_en":"No translation.","title_de":null,"body_de":null,"created_at":"2026-11-15T10:00:00+00:00","expires_at":"2026-12-01T00:00:00+00:00"}
]"""

class AnnouncementTests {
    private fun withApi(block: suspend (MockWebServer, AnnouncementsApi) -> Unit) {
        MockWebServer().use { server ->
            server.start()
            // Signed out: the token function never gives a token.
            runBlocking { block(server, AnnouncementsApi(Rest(server.url("/").toString(), "pub-key", { null }))) }
        }
    }

    @Test
    fun theyAreReadWithoutBeingSignedIn() = withApi { server, api ->
        server.enqueue(MockResponse.Builder().code(200).body(ROWS).build())
        val items = api.fetch()
        assertEquals(listOf("a1", "a2"), items.map { it.id })
        val request = server.takeRequest()
        assertEquals("/rest/v1/rpc/get_announcements", request.url.encodedPath)
        assertEquals("pub-key", request.headers["apikey"])
        assertNull(request.headers["Authorization"])
    }

    @Test
    fun aServerErrorIsAnException() = withApi { server, api ->
        server.enqueue(MockResponse.Builder().code(503).build())
        try { api.fetch(); error("should have thrown") } catch (e: ApiException.Retry) { }
        server.enqueue(MockResponse.Builder().code(404).body("""{"code":"PGRST202"}""").build())
        try { api.fetch(); error("should have thrown") } catch (e: ApiException.Failed) { assertEquals(404, e.status) }
    }

    @Test
    fun germanIsUsedWhenThereIsAnyElseEnglish() = withApi { server, api ->
        server.enqueue(MockResponse.Builder().code(200).body(ROWS).build())
        val (translated, english) = api.fetch()
        assertEquals("Kleine Liste" to "Die Typenliste bleibt klein.", translated.text("de"))
        assertEquals("Small list" to "The type list stays small.", translated.text("en"))
        assertEquals("Small list" to "The type list stays small.", translated.text("fr"))
        assertEquals("English only" to "No translation.", english.text("de"))
    }

    @Test
    fun dismissedOnesAreLeftOut() = withApi { server, api ->
        server.enqueue(MockResponse.Builder().code(200).body(ROWS).build())
        val items = api.fetch()
        assertEquals(listOf("a2"), visibleAnnouncements(items, setOf("a1")).map { it.id })
        assertEquals(emptyList(), visibleAnnouncements(items, setOf("a1", "a2")))
    }

    @Test
    fun theKeptCopyComesBackTheSame() = withApi { server, api ->
        server.enqueue(MockResponse.Builder().code(200).body(ROWS).build())
        val items = api.fetch()
        assertEquals(items, api.decode(api.encode(items)))
        assertEquals(emptyList(), api.decode("not json"))
    }
}
