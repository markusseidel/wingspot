package site.wingspot.core

import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.execSQL
import java.io.File
import java.security.MessageDigest
import kotlin.io.path.createTempDirectory
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlinx.coroutines.runBlocking
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import okio.Buffer

/** A small snapshot built from the real schema in `contracts/refdata/schema.sql`. */
private fun buildSnapshot(file: File, schemaVersion: Int = 2, dataVersion: String = "2026-11-09") {
    val schema = File("../../contracts/refdata/schema.sql").readText()
        .lines().filterNot { it.trimStart().startsWith("--") }.joinToString("\n")
        .replace("PRAGMA user_version = 2", "PRAGMA user_version = $schemaVersion")
    val db = BundledSQLiteDriver().open(file.path)
    try {
        for (statement in schema.split(";").map { it.trim() }.filter { it.isNotEmpty() }) db.execSQL(statement)
        db.execSQL("INSERT INTO meta VALUES ('data_version', '$dataVersion')")
        db.execSQL(
            """INSERT INTO airports (id, icao, iata, name, city, country_code, continent, type, latitude, longitude, default_search, keywords) VALUES
              (1, 'EDDF', 'FRA', 'Frankfurt am Main Airport', 'Frankfurt', 'DE', 'EU', 'large_airport', 50.033, 8.571, 1, 'Flughafen Frankfurt'),
              (2, 'EDDM', 'MUC', 'Munich Airport', 'Munich', 'DE', 'EU', 'large_airport', 48.354, 11.786, 1, 'Flughafen München Franz Josef Strauss'),
              (3, 'EDFE', NULL, 'Frankfurt-Egelsbach Airport', 'Egelsbach', 'DE', 'EU', 'small_airport', 49.96, 8.64, 0, NULL)""",
        )
        db.execSQL("INSERT INTO airports_fts(airports_fts) VALUES ('rebuild')")
        db.execSQL(
            """INSERT INTO aircraft_types (icao_code, manufacturer, model, family) VALUES
              ('A320', 'Airbus', 'A320', 'A320'), ('A20N', 'Airbus', 'A320neo', 'A320'),
              ('CRJ9', 'Bombardier', 'CRJ-900', 'CRJ'), ('B738', 'Boeing', '737-800', '737')""",
        )
        db.execSQL("INSERT INTO aircraft_types_fts (icao_code, manufacturer, model, family) SELECT icao_code, manufacturer, model, family FROM aircraft_types")
    } finally {
        db.close()
    }
}

private fun sha256(file: File) = MessageDigest.getInstance("SHA-256").digest(file.readBytes()).joinToString("") { "%02x".format(it) }

class ReferenceDataTests {
    private fun tempDir() = createTempDirectory("refdata").toFile()

    private fun database(): ReferenceDatabase {
        val file = File(tempDir(), "snapshot.sqlite")
        buildSnapshot(file)
        return ReferenceDatabase.open(file.path)
    }

    @Test
    fun searchQueriesAreBuiltLikeOnTheIPhone() {
        assertEquals("\"munich\"*", SearchQuery.fts("Munich"))
        assertEquals("(\"crj900\"* OR (\"crj\"* \"900\"*))", SearchQuery.fts("crj900"))
        assertEquals("\"crj\"* \"900\"*", SearchQuery.fts("CRJ-900"))
        assertNull(SearchQuery.fts("  - "))
    }

    @Test
    fun typesAreFoundByCodeMakerOrModel() = runBlocking {
        val db = database()
        assertEquals("A320", db.searchTypes("a320").first().icaoCode, "the exact code comes first")
        assertEquals(setOf("A320", "A20N"), db.searchTypes("a320").map { it.icaoCode }.toSet())
        assertEquals(listOf("CRJ9"), db.searchTypes("crj900").map { it.icaoCode })
        assertEquals(listOf("B738"), db.searchTypes("boeing").map { it.icaoCode })
        assertEquals("Boeing 737-800", db.aircraftType("b738")!!.name)
        assertNull(db.aircraftType("ZZZZ"))
        assertEquals(emptyList(), db.searchTypes("  "))
    }

    @Test
    fun airportsAreFoundByNameKeywordOrCodeWithExactCodesFirst() = runBlocking {
        val db = database()
        assertEquals("FRA", db.searchAirports("fra").first().code)
        assertEquals("MUC", db.searchAirports("flughafen münchen").first().code)
        assertEquals("MUC", db.searchAirports("munich").first().code)
        // The large airport comes before the small one with a similar name.
        assertEquals(listOf("FRA", "EDFE"), db.searchAirports("frankfurt").map { it.code })
        assertEquals(48.354, db.airport("muc")!!.latitude)
        assertNull(db.airport("XXX"))
    }

    @Test
    fun anotherSchemaVersionIsRefused() {
        val file = File(tempDir(), "old.sqlite")
        buildSnapshot(file, schemaVersion = 1)
        val error = assertFailsWith<ReferenceDataException.UnsupportedSchema> { ReferenceDatabase.open(file.path) }
        assertEquals(1, error.version)
    }

    private fun withServer(snapshot: File, advertisedSha: String? = null, block: (MockWebServer, ReferenceDataInstaller, RefdataManifest, File) -> Unit) {
        MockWebServer().use { server ->
            server.start()
            val dir = tempDir()
            val manifest = RefdataManifest(2, "2026-11-09", server.url("/snapshot.sqlite").toString(), advertisedSha ?: sha256(snapshot), snapshot.length())
            server.enqueue(MockResponse.Builder().code(200).body(Buffer().write(snapshot.readBytes())).build())
            block(server, ReferenceDataInstaller(dir, server.url("/").toString(), requireHttps = false), manifest, dir)
        }
    }

    @Test
    fun aSnapshotIsDownloadedCheckedAndInstalled() {
        val snapshot = File(tempDir(), "s.sqlite").also { buildSnapshot(it) }
        withServer(snapshot) { _, installer, manifest, _ ->
            assertNull(installer.installed())
            val db = runBlocking { installer.install(manifest) }
            assertEquals("2026-11-09", db.dataVersion)
            assertEquals("MUC", runBlocking { db.searchAirports("munich") }.first().code)
            assertEquals("2026-11-09", installer.installed()!!.dataVersion)
        }
    }

    @Test
    fun aBadDownloadNeverReplacesAWorkingDatabase() {
        val good = File(tempDir(), "good.sqlite").also { buildSnapshot(it, dataVersion = "old") }
        val newer = File(tempDir(), "new.sqlite").also { buildSnapshot(it, dataVersion = "new") }
        withServer(newer, advertisedSha = "0".repeat(64)) { _, installer, manifest, dir ->
            good.copyTo(installer.databaseFile)
            assertFailsWith<ReferenceDataException.ChecksumMismatch> { runBlocking { installer.install(manifest) } }
            assertEquals("old", installer.installed()!!.dataVersion)
            assertEquals(listOf("refdata.sqlite"), dir.list()!!.toList(), "no half-downloaded file is left")
        }
    }

    @Test
    fun theWrongSizeIsRefused() {
        val snapshot = File(tempDir(), "s.sqlite").also { buildSnapshot(it) }
        withServer(snapshot) { _, installer, manifest, _ ->
            assertFailsWith<ReferenceDataException.SizeMismatch> { runBlocking { installer.install(manifest.copy(sizeBytes = manifest.sizeBytes + 1)) } }
        }
    }

    @Test
    fun onlyHttpsAndKnownSchemasAreAccepted() {
        val installer = ReferenceDataInstaller(tempDir(), "http://localhost/")
        val manifest = RefdataManifest(2, "v", "http://example.test/x.sqlite", "0".repeat(64), 1)
        assertFailsWith<ReferenceDataException.InsecureUrl> { runBlocking { installer.install(manifest) } }
        assertFailsWith<ReferenceDataException.UnsupportedSchema> { runBlocking { installer.install(manifest.copy(schemaVersion = 3)) } }
    }

    @Test
    fun theManifestIsReadAndAMissingOneIsNull() {
        MockWebServer().use { server ->
            server.start()
            val installer = ReferenceDataInstaller(tempDir(), server.url("/functions").toString())
            server.enqueue(MockResponse.Builder().code(200).body("""{"schema_version":2,"data_version":"2026-11-04","url":"https://x.test/s","sha256":"${"a".repeat(64)}","size_bytes":10,"extra":1}""").build())
            assertEquals("2026-11-04", runBlocking { installer.manifest() }!!.dataVersion)
            assertEquals("/functions/v1/refdata/manifest", server.takeRequest().url.encodedPath)
            server.enqueue(MockResponse.Builder().code(404).body("{}").build())
            assertNull(runBlocking { installer.manifest() })
            server.enqueue(MockResponse.Builder().code(500).body("x").build())
            assertFailsWith<ReferenceDataException.Download> { runBlocking { installer.manifest() } }
        }
    }
}
