package site.wingspot.core

import androidx.sqlite.SQLiteConnection
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.driver.bundled.SQLITE_OPEN_READONLY
import java.io.File
import java.io.IOException
import java.security.MessageDigest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request

data class Airport(
    val id: Long, val icao: String?, val iata: String?, val name: String, val city: String?,
    val latitude: Double, val longitude: Double,
) {
    /** The shortest label people recognize: IATA, then ICAO, then the name. */
    val code: String get() = iata ?: icao ?: name
}

data class AircraftType(val icaoCode: String, val manufacturer: String, val model: String) {
    val name: String get() = "$manufacturer $model"
}

@Serializable
data class RefdataManifest(
    @SerialName("schema_version") val schemaVersion: Int,
    @SerialName("data_version") val dataVersion: String,
    val url: String,
    val sha256: String,
    @SerialName("size_bytes") val sizeBytes: Long,
)

sealed class ReferenceDataException(message: String) : Exception(message) {
    class UnsupportedSchema(val version: Int) : ReferenceDataException("unsupportedSchema $version")
    object InsecureUrl : ReferenceDataException("insecureUrl")
    object SizeMismatch : ReferenceDataException("sizeMismatch")
    object ChecksumMismatch : ReferenceDataException("checksumMismatch")
    object Download : ReferenceDataException("download")
}

/**
 * The read-only reference database (airports and aircraft types) the app downloads once and searches offline.
 * The schema is `contracts/refdata/schema.sql`, shared with the iPhone app.
 */
class ReferenceDatabase private constructor(private val connection: SQLiteConnection, val dataVersion: String) {
    private val lock = Mutex()

    /** Finds types by code, maker or model, with an exact code first. */
    suspend fun searchTypes(text: String, limit: Int = 30): List<AircraftType> {
        val query = SearchQuery.fts(text) ?: return emptyList()
        val code = text.trim().uppercase()
        return query(
            """
            SELECT t.icao_code, t.manufacturer, t.model
            FROM aircraft_types_fts f
            JOIN aircraft_types t ON t.icao_code = f.icao_code
            WHERE aircraft_types_fts MATCH ?
            ORDER BY t.icao_code = ? DESC, f.rank
            LIMIT ?
            """,
            { it.bindText(1, query); it.bindText(2, code); it.bindLong(3, limit.toLong()) },
        ) { AircraftType(it.getText(0), it.getText(1), it.getText(2)) }
    }

    /** Finds airports by name, city, code or keyword: exact codes first, then large airports. */
    suspend fun searchAirports(text: String, limit: Int = 30): List<Airport> {
        val query = SearchQuery.fts(text) ?: return emptyList()
        val code = text.trim().uppercase()
        return query(
            """
            SELECT a.id, a.icao, a.iata, a.name, a.city, a.latitude, a.longitude FROM airports_fts f
            JOIN airports a ON a.id = f.rowid
            WHERE airports_fts MATCH ?
            ORDER BY a.iata = ? DESC, a.icao = ? DESC,
              CASE a.type WHEN 'large_airport' THEN 0 WHEN 'medium_airport' THEN 1 ELSE 2 END,
              a.default_search DESC, f.rank
            LIMIT ?
            """,
            { it.bindText(1, query); it.bindText(2, code); it.bindText(3, code); it.bindLong(4, limit.toLong()) },
        ) { airport(it) }
    }

    suspend fun aircraftType(icao: String): AircraftType? = query(
        "SELECT icao_code, manufacturer, model FROM aircraft_types WHERE icao_code = ?",
        { it.bindText(1, icao.trim().uppercase()) },
    ) { AircraftType(it.getText(0), it.getText(1), it.getText(2)) }.firstOrNull()

    /** The airport with this IATA code. Boarding passes carry IATA codes. */
    suspend fun airport(iata: String): Airport? = query(
        """
        SELECT id, icao, iata, name, city, latitude, longitude FROM airports WHERE iata = ?
        ORDER BY CASE type WHEN 'large_airport' THEN 0 WHEN 'medium_airport' THEN 1 ELSE 2 END, default_search DESC
        LIMIT 1
        """,
        { it.bindText(1, iata.trim().uppercase()) },
    ) { airport(it) }.firstOrNull()

    /** The airport with this id in the reference data, for example a home airport saved on the server. */
    suspend fun airport(id: Long): Airport? = query(
        "SELECT id, icao, iata, name, city, latitude, longitude FROM airports WHERE id = ?",
        { it.bindLong(1, id) },
    ) { airport(it) }.firstOrNull()

    private fun airport(row: androidx.sqlite.SQLiteStatement) = Airport(
        row.getLong(0), row.textOrNull(1), row.textOrNull(2), row.getText(3), row.textOrNull(4), row.getDouble(5), row.getDouble(6),
    )

    private fun androidx.sqlite.SQLiteStatement.textOrNull(index: Int) = if (isNull(index)) null else getText(index)

    private suspend fun <T> query(
        sql: String, bind: (androidx.sqlite.SQLiteStatement) -> Unit, read: (androidx.sqlite.SQLiteStatement) -> T,
    ): List<T> = withContext(Dispatchers.IO) {
        lock.withLock {
            connection.prepare(sql.trimIndent()).use { statement ->
                bind(statement)
                buildList { while (statement.step()) add(read(statement)) }
            }
        }
    }

    fun close() = connection.close()

    companion object {
        const val SUPPORTED_SCHEMA_VERSION = 2

        /** Opens a snapshot read-only. Throws [ReferenceDataException.UnsupportedSchema] for another schema version. */
        fun open(path: String): ReferenceDatabase {
            val connection = BundledSQLiteDriver().open(path, SQLITE_OPEN_READONLY)
            try {
                val schema = connection.prepare("PRAGMA user_version").use { it.step(); it.getLong(0).toInt() }
                if (schema != SUPPORTED_SCHEMA_VERSION) throw ReferenceDataException.UnsupportedSchema(schema)
                val version = connection.prepare("SELECT value FROM meta WHERE key = 'data_version'").use {
                    if (it.step()) it.getText(0) else ""
                }
                return ReferenceDatabase(connection, version)
            } catch (e: Throwable) {
                connection.close()
                throw e
            }
        }
    }
}

/** Fetches the manifest and installs the snapshot it points to into [directory]. */
class ReferenceDataInstaller(
    private val directory: File,
    private val functionsUrl: String,
    private val client: OkHttpClient = OkHttpClient(),
    /** Tests turn this off to use a plain local server. */
    private val requireHttps: Boolean = true,
) {
    private val json = Json { ignoreUnknownKeys = true }
    val databaseFile: File get() = File(directory, "refdata.sqlite")

    /** The snapshot on this phone, or null if there is none or it can't be opened. */
    fun installed(): ReferenceDatabase? =
        if (databaseFile.exists()) runCatching { ReferenceDatabase.open(databaseFile.path) }.getOrNull() else null

    /** The current manifest, or null if no snapshot has been published yet (404). */
    suspend fun manifest(): RefdataManifest? = withContext(Dispatchers.IO) {
        val request = Request.Builder().url("${functionsUrl.trimEnd('/')}/v1/refdata/manifest").build()
        try {
            client.newCall(request).execute().use { response ->
                when {
                    response.code == 404 -> null
                    response.isSuccessful -> json.decodeFromString(RefdataManifest.serializer(), response.body.string())
                    else -> throw ReferenceDataException.Download
                }
            }
        } catch (e: IOException) {
            throw ReferenceDataException.Download
        }
    }

    /** Downloads, checks and swaps in the snapshot. A bad download never replaces a working database. */
    suspend fun install(manifest: RefdataManifest): ReferenceDatabase = withContext(Dispatchers.IO) {
        if (manifest.schemaVersion != ReferenceDatabase.SUPPORTED_SCHEMA_VERSION) {
            throw ReferenceDataException.UnsupportedSchema(manifest.schemaVersion)
        }
        if (requireHttps && !manifest.url.startsWith("https://")) throw ReferenceDataException.InsecureUrl
        directory.mkdirs()
        val candidate = File(directory, "refdata-${System.nanoTime()}.sqlite")
        try {
            val digest = MessageDigest.getInstance("SHA-256")
            var size = 0L
            try {
                client.newCall(Request.Builder().url(manifest.url).build()).execute().use { response ->
                    if (!response.isSuccessful) throw ReferenceDataException.Download
                    response.body.byteStream().use { input ->
                        candidate.outputStream().use { output ->
                            val buffer = ByteArray(64 * 1024)
                            while (true) {
                                val n = input.read(buffer)
                                if (n < 0) break
                                digest.update(buffer, 0, n)
                                output.write(buffer, 0, n)
                                size += n
                            }
                        }
                    }
                }
            } catch (e: IOException) {
                throw ReferenceDataException.Download
            }
            if (size != manifest.sizeBytes) throw ReferenceDataException.SizeMismatch
            if (digest.digest().joinToString("") { "%02x".format(it) } != manifest.sha256) throw ReferenceDataException.ChecksumMismatch
            ReferenceDatabase.open(candidate.path).close() // checks the schema before it replaces anything
            java.nio.file.Files.move(
                candidate.toPath(), databaseFile.toPath(),
                java.nio.file.StandardCopyOption.REPLACE_EXISTING, java.nio.file.StandardCopyOption.ATOMIC_MOVE,
            )
            ReferenceDatabase.open(databaseFile.path)
        } finally {
            candidate.delete()
        }
    }
}
