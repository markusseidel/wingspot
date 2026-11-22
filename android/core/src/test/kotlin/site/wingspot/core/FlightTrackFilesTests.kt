package site.wingspot.core

import java.io.File
import java.nio.file.Files
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.runBlocking

class FlightTrackFilesTests {
    private fun directory() = Files.createTempDirectory("tracks").toFile()
    private val sample = listOf(GeoCoordinate(50.03, 8.57), GeoCoordinate(40.64, -73.78), GeoCoordinate(-33.5, 179.999999))

    @Test
    fun aTrackIsSavedAndLoadedExactly() {
        val files = FlightTrackFiles(directory())
        val id = UUID.randomUUID()
        assertNull(files.load(id))
        assertFalse(files.has(id))
        files.save(sample, id)
        assertTrue(files.has(id))
        assertEquals(sample, files.load(id))
    }

    @Test
    fun theFileHasTheLayoutBothAppsShare() {
        val dir = directory()
        val id = UUID.randomUUID()
        FlightTrackFiles(dir).save(listOf(GeoCoordinate(2.0, 1.0)), id)
        val data = File(dir, "${id.toString().lowercase()}.trk").readBytes()
        assertEquals(4 + 16, data.size)
        assertContentEquals("WTR1".toByteArray(), data.copyOfRange(0, 4))
        // 1.0 as little-endian IEEE 754 is 00 00 00 00 00 00 F0 3F
        assertContentEquals(byteArrayOf(0, 0, 0, 0, 0, 0, 0xF0.toByte(), 0x3F), data.copyOfRange(4, 12))
    }

    @Test
    fun aDamagedFileIsNotATrack() {
        val dir = directory()
        val files = FlightTrackFiles(dir)
        val id = UUID.randomUUID()
        files.save(sample, id)
        val path = File(dir, "${id.toString().lowercase()}.trk")
        path.writeText("junk")
        assertNull(files.load(id))
        path.writeText("WTR1abc")
        assertNull(files.load(id))
    }

    @Test
    fun deletingRemovesTheFile() {
        val files = FlightTrackFiles(directory())
        val a = UUID.randomUUID()
        val b = UUID.randomUUID()
        files.save(sample, a)
        files.save(sample, b)
        files.delete(a)
        assertNull(files.load(a))
        assertNotNull(files.load(b))
        files.deleteAll()
        assertFalse(files.has(b))
    }

    @Test
    fun deletingAFlightAndEverythingRemoveTheirTracks() = runBlocking {
        val files = FlightTrackFiles(directory())
        val store = CheckInStore.open(":memory:", files)
        val draft = FlownDraft(Place(1, "AAA"), Place(2, "BBB"))
        val first = store.saveFlown(draft)
        val second = store.saveFlown(draft)
        files.save(sample, first.id)
        files.save(sample, second.id)
        store.delete(first.id)
        assertNull(files.load(first.id))
        assertEquals(sample, files.load(second.id))
        store.deleteEverything()
        assertNull(files.load(second.id))
    }
}

class KmlSwitchesTests {
    @Test
    fun switchesAreOnWhenTheServerSaysNothing() {
        assertEquals(KmlSwitches(importOn = true, keepRoutes = true), KmlSwitches.from(emptyMap()))
        assertEquals(KmlSwitches(importOn = true, keepRoutes = true), KmlSwitches.from(mapOf("feed" to false)))
    }

    @Test
    fun switchesFollowTheServer() {
        assertEquals(KmlSwitches(false, false), KmlSwitches.from(mapOf("kml_import" to false, "kml_tracks_keep" to false)))
        assertEquals(KmlSwitches(false, true), KmlSwitches.from(mapOf("kml_import" to false)))
    }

    @Test
    fun theConfigCallReadsTheFlagsAndIgnoresOtherValues() {
        mockwebserver3.MockWebServer().use { server ->
            server.start()
            server.enqueue(mockwebserver3.MockResponse.Builder().code(200).body(
                """{"min_version":{"ios":"0.1.0","android":"0.1.0"},"feature_flags":{"kml_import":false,"other":"text"}}""",
            ).build())
            val flags: Map<String, Boolean> = kotlinx.coroutines.runBlocking { ApiClient(server.url("/functions").toString()).featureFlags() }
            assertEquals(mapOf("kml_import" to false), flags)
            server.enqueue(mockwebserver3.MockResponse.Builder().code(500).body("{}").build())
            kotlin.test.assertFailsWith<ApiException.Retry> { kotlinx.coroutines.runBlocking { ApiClient(server.url("/functions").toString()).featureFlags() } }
            Unit
        }
    }
}
