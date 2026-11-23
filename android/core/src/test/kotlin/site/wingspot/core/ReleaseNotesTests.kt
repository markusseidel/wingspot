package site.wingspot.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.runBlocking
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer

private const val NOTE_ROWS = """[
  {"id":"n8","version":"0.2.0","build":2026112308,"kind":"beta","title_en":"Eight","body_en":"- three","title_de":null,"body_de":null,"released_at":"2026-11-23T20:00:00+00:00","something_new":1},
  {"id":"n7","version":"0.2.0","build":2026112307,"kind":"beta","title_en":"Seven","body_en":"- one\n- two","title_de":"Sieben","body_de":"- eins\n- zwei","released_at":"2026-11-23T10:00:00+00:00"}
]"""

class ReleaseNotesTests {
    private fun note(build: Long) = ReleaseNote("id$build", "0.2.0", build, titleEn = "T$build", bodyEn = "- x")

    @Test
    fun theyAreReadWithoutBeingSignedInAndAskForAndroid() {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(MockResponse.Builder().code(200).body(NOTE_ROWS).build())
            val api = ReleaseNotesApi(Rest(server.url("/").toString(), "pub-key", { null }))
            val items = runBlocking { api.fetch() }
            assertEquals(listOf(2026112308L, 2026112307L), items.map { it.build })
            val request = server.takeRequest()
            assertEquals("/rest/v1/rpc/get_release_notes", request.url.encodedPath)
            assertTrue(request.body!!.utf8().contains("\"android\""))
            assertNull(request.headers["Authorization"]?.takeIf { it.contains("null") })
            assertEquals("2026-11-23", items[0].day)
            assertTrue(items[0].isBeta)
        }
    }

    @Test
    fun theKeptCopyRoundTripsAndABrokenOneIsEmpty() {
        val api = ReleaseNotesApi(Rest("http://x", "k", { null }))
        val items = api.decode(NOTE_ROWS)
        assertEquals(items, api.decode(api.encode(items)))
        assertEquals(emptyList(), api.decode("not json"))
    }

    @Test
    fun bulletsBecomeLinesAndGermanFallsBackToEnglish() {
        assertEquals(listOf("one", "two", "plain"), ReleaseNote.linesOf("- one\n\n  - two \nplain"))
        val items = ReleaseNotesApi(Rest("http://x", "k", { null })).decode(NOTE_ROWS)
        assertEquals("Sieben" to listOf("eins", "zwei"), items[1].text("de"))
        assertEquals("Seven", items[1].text("en").first)
        assertEquals("Eight", items[0].text("de").first)
    }

    @Test
    fun newerBuildsComeFirstAndTheInstalledOneSplitsTheList() {
        val groups = groupReleaseNotes(listOf(note(2026112307), note(2026112309), note(2026112308)), installedBuild = 2026112308)
        assertEquals(listOf(2026112309L), groups.newer.map { it.build })
        assertEquals(listOf(2026112308L, 2026112307L), groups.installedAndOlder.map { it.build })
    }
}
