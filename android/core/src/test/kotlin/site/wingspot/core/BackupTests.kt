package site.wingspot.core

import java.io.ByteArrayInputStream
import java.io.File
import java.nio.file.Files
import java.time.Instant
import java.util.UUID
import java.util.zip.GZIPInputStream
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlinx.coroutines.runBlocking

/** The made-up backup the iPhone app reads too, from `contracts/test-vectors/backup/`. */
class BackupTests {
    private fun vector(name: String) = File("../../contracts/test-vectors/backup/$name").readBytes()
    private fun tracks() = FlightTrackFiles(Files.createTempDirectory("tracks").toFile())
    private fun store(tracks: FlightTrackFiles) = CheckInStore.open(":memory:", tracks)

    private val flightId = UUID.fromString("019a0000-0000-7000-8000-000000000001")
    private val spottedId = UUID.fromString("019a0000-0000-7000-8000-000000000002")
    private val orphanRouteId = UUID.fromString("019a0000-0000-7000-8000-00000000000a")

    @Test
    fun theSharedVectorReadsTheSameZippedAndPlain() {
        val zipped = BackupCodec.decode(vector("example.wingspotbackup"))
        val plain = BackupCodec.decode(vector("example.json"))
        assertEquals(plain, zipped)
        assertEquals(1, plain.schema)
        assertEquals("android", plain.platform)
        assertEquals(2, plain.routes.features.size)
        assertEquals(2, plain.checkins.size)
        assertEquals(listOf(-73.77814, 40.64131), plain.routes.features[0].geometry.coordinates[2])
        assertEquals("A359", plain.checkins[0].typeIcao)
        assertEquals(false, plain.checkins[0].timeKnown)
    }

    @Test
    fun theSchema2VectorReadsWithWhatTheServerHas() = runBlocking {
        val zipped = BackupCodec.decode(vector("example-schema2.wingspotbackup"))
        val plain = BackupCodec.decode(vector("example-schema2.json"))
        assertEquals(plain, zipped)
        assertEquals(2, plain.schema)
        assertEquals(3, plain.checkins.size)
        assertEquals(true, plain.checkins.last().onServer)
        assertEquals("019a0000-0000-7000-8000-0000000000ff", plain.checkins.last().ownerId)
        val tracks = tracks()
        val store = store(tracks)
        assertEquals(BackupResult(2, 3, 0), BackupService(store, tracks).restore(plain, replaceRoutes = false))
        val visit = store.all().first { it.id.toString() == "019a0000-0000-7000-8000-000000000003" }
        assertEquals(SyncState.SYNCED, visit.syncState)
        assertEquals("departing", visit.visitContext)
    }

    @Test
    fun whatIsNotABackupIsTold() {
        assertFailsWith<BackupException.NotBackup> { BackupCodec.decode("hello".toByteArray()) }
        assertFailsWith<BackupException.NotBackup> { BackupCodec.decode("""{"format":"other","schema":1}""".toByteArray()) }
        assertFailsWith<BackupException.NewerVersion> { BackupCodec.decode("""{"format":"wingspot-backup","schema":99}""".toByteArray()) }
        assertFailsWith<BackupException.Damaged> { BackupCodec.decode(vector("truncated.wingspotbackup")) }
        val cut = vector("example.wingspotbackup").let { it.copyOfRange(0, it.size - 20) }
        assertFailsWith<BackupException.Damaged> { BackupCodec.decode(cut) }
    }

    @Test
    fun aBackupRestoresOnAnEmptyPhone() = runBlocking {
        val tracks = tracks()
        val store = store(tracks)
        val result = BackupService(store, tracks).restore(BackupCodec.decode(vector("example.json")), replaceRoutes = false)
        assertEquals(BackupResult(routes = 2, checkIns = 2, skipped = 0), result)
        assertEquals(setOf(flightId, spottedId), store.all().map { it.id }.toSet())
        val flight = assertNotNull(store.find(flightId))
        assertEquals(SyncState.PENDING, flight.syncState)
        assertFalse(flight.timeKnown)
        assertEquals("34K", flight.seat)
        assertEquals("FRA", flight.originCode)
        assertEquals(Instant.parse("2026-08-12T18:30:00Z"), flight.savedAt)
        // A route whose flight is not here yet is kept for when it arrives.
        assertEquals(2, tracks.load(orphanRouteId)?.size)
        assertEquals(GeoCoordinate(40.64131, -73.77814), tracks.load(flightId)?.last())
    }

    @Test
    fun restoringTwiceAddsNothingAndReplacingIsAChoice() = runBlocking {
        val tracks = tracks()
        val service = BackupService(store(tracks), tracks)
        val document = BackupCodec.decode(vector("example.json"))
        service.restore(document, replaceRoutes = false)
        tracks.save(listOf(GeoCoordinate(1.0, 1.0), GeoCoordinate(2.0, 2.0)), flightId)
        assertEquals(BackupResult(0, 0, 4), service.restore(document, replaceRoutes = false))
        assertEquals(2, tracks.load(flightId)?.size)
        assertEquals(BackupResult(2, 0, 2), service.restore(document, replaceRoutes = true))
        assertEquals(3, tracks.load(flightId)?.size)
    }

    @Test
    fun aBackupHoldsRoutesAndEveryCheckIn() = runBlocking {
        val tracks = tracks()
        val store = store(tracks)
        val flown = store.saveFlown(FlownDraft(Place(2212, "FRA"), Place(3797, "JFK"), flightNumber = "LH400"))
        val sent = store.saveSpotted(SpottedDraft(registration = Registration.parse("DAIMA")))
        store.markSynced(listOf(sent.id))
        tracks.save(listOf(GeoCoordinate(50.033333333, 8.570634567), GeoCoordinate(40.64, -73.78)), flown.id)

        val document = BackupService(store, tracks).make("Wingspot test", Instant.EPOCH)
        // The flight, the two airport visits it made, and the sighting the server has, marked as such.
        assertTrue(document.checkins.any { it.id == flown.id.toString() })
        assertEquals(4, document.checkins.size)
        assertEquals(listOf(sent.id.toString()), document.checkins.filter { it.onServer == true }.map { it.id })
        assertEquals(2, document.schema)
        assertEquals("LH400", document.routes.features.first().properties.flightNumber)
        assertEquals("1970-01-01T00:00:00Z", document.createdAt)

        val data = BackupCodec.encode(document)
        val json = String(GZIPInputStream(ByteArrayInputStream(data)).readBytes())
        assertTrue("[8.57063,50.03333]" in json, json)
        assertTrue("\"checkin_id\":\"" in json && "\"type\":\"FeatureCollection\"" in json)
        assertTrue("\"on_server\":true" in json, json)

        // Round trip onto another phone.
        val otherTracks = tracks()
        val otherStore = store(otherTracks)
        val result = BackupService(otherStore, otherTracks).restore(BackupCodec.decode(data), replaceRoutes = false)
        assertEquals(BackupResult(1, 4, 0), result)
        // The sighting the server has is not sent again.
        assertEquals(SyncState.SYNCED, otherStore.all().first { it.id == sent.id }.syncState)
        assertEquals(3, otherStore.all().count { it.syncState == SyncState.PENDING })
        assertEquals(GeoCoordinate(50.03333, 8.57063), otherTracks.load(flown.id)?.first())
    }

    @Test
    fun thePreviewCountsRoutesWhoseFlightIsHere() = runBlocking {
        val tracks = tracks()
        val service = BackupService(store(tracks), tracks)
        val document = BackupCodec.decode(vector("example.json"))
        // The flight of the first route is in the file; the second route's flight is nowhere.
        assertEquals(1, service.preview(document).routesWithFlightHere)
        service.restore(document, replaceRoutes = false)
        val preview = service.preview(document)
        assertEquals(2, preview.routes)
        assertEquals(2, preview.checkIns)
        assertEquals(1, preview.routesWithFlightHere)
    }
}
