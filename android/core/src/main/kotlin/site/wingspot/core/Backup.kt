package site.wingspot.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.temporal.ChronoUnit
import java.util.UUID
import java.util.zip.GZIPInputStream
import java.util.zip.GZIPOutputStream
import kotlin.math.roundToLong

/** What can go wrong when reading a backup, in the words the restore screen uses. */
sealed class BackupException : Exception() {
    /** Not a Wingspot backup at all. */
    object NotBackup : BackupException() { private fun readResolve(): Any = NotBackup }

    /** Made by a newer Wingspot with a layout this app does not know. */
    object NewerVersion : BackupException() { private fun readResolve(): Any = NewerVersion }

    /** A Wingspot backup that cannot be read: cut off or changed. */
    object Damaged : BackupException() { private fun readResolve(): Any = Damaged }
}

/**
 * The backup file (docs/BACKUP-FORMAT.md): the routes of imported flights and the check-ins only this phone has, as one
 * gzip-compressed JSON document. The same layout is written and read by the iPhone app.
 */
@Serializable
data class BackupDocument(
    val format: String,
    val schema: Int,
    @SerialName("created_at") val createdAt: String,
    val app: String? = null,
    val platform: String? = null,
    val counts: Counts? = null,
    val routes: Routes,
    val checkins: List<BackupCheckIn>,
) {
    @Serializable
    data class Counts(val routes: Int, val checkins: Int)

    /** A GeoJSON FeatureCollection, so it can be cut out of the file and opened in any map tool. */
    @Serializable
    data class Routes(val type: String = "FeatureCollection", val features: List<Feature>)

    @Serializable
    data class Feature(val type: String = "Feature", val properties: Properties, val geometry: Geometry)

    @Serializable
    data class Properties(
        @SerialName("checkin_id") val checkinId: String,
        @SerialName("flight_number") val flightNumber: String? = null,
        val origin: String? = null,
        val destination: String? = null,
        val day: String? = null,
    )

    /** [coordinates] are `[longitude, latitude]` pairs. */
    @Serializable
    data class Geometry(val type: String = "LineString", val coordinates: List<List<Double>>)

    /** When the backup was made, if the date can be read. */
    val created: Instant? get() = BackupDates.parse(createdAt)

    companion object {
        const val FORMAT = "wingspot-backup"
        const val SCHEMA = 1
    }
}

/** A check-in in the backup. Ids are text, in lower case. */
@Serializable
data class BackupCheckIn(
    val id: String,
    val kind: String,
    @SerialName("occurred_at") val occurredAt: String,
    @SerialName("time_known") val timeKnown: Boolean? = null,
    @SerialName("saved_at") val savedAt: String? = null,
    val registration: String? = null,
    @SerialName("type_icao") val typeIcao: String? = null,
    @SerialName("type_name") val typeName: String? = null,
    @SerialName("airport_id") val airportId: Long? = null,
    @SerialName("airport_code") val airportCode: String? = null,
    val latitude: Double? = null,
    val longitude: Double? = null,
    @SerialName("visit_context") val visitContext: String? = null,
    @SerialName("spot_id") val spotId: Long? = null,
    @SerialName("spot_name") val spotName: String? = null,
    @SerialName("visit_id") val visitId: String? = null,
    @SerialName("origin_id") val originId: Long? = null,
    @SerialName("origin_code") val originCode: String? = null,
    @SerialName("destination_id") val destinationId: Long? = null,
    @SerialName("destination_code") val destinationCode: String? = null,
    @SerialName("flight_number") val flightNumber: String? = null,
    val cabin: String? = null,
    val seat: String? = null,
    @SerialName("flight_id") val flightId: String? = null,
    @SerialName("source_id") val sourceId: String? = null,
)

internal object BackupDates {
    fun parse(text: String): Instant? = runCatching { Instant.parse(text) }.getOrNull()

    /** Whole seconds, like the iPhone app writes them. */
    fun format(instant: Instant): String = instant.truncatedTo(ChronoUnit.SECONDS).toString()

    fun day(instant: Instant): String = LocalDate.ofInstant(instant, ZoneOffset.UTC).toString()
}

/** Writes and reads the file: JSON, gzip around it. Reading also takes the plain, unzipped JSON. */
object BackupCodec {
    /** Bigger than any real backup (100 flights take tens of megabytes); a file that unzips to more is refused. */
    const val MAXIMUM_SIZE = 200 * 1024 * 1024

    private val json = Json { ignoreUnknownKeys = true; explicitNulls = false; encodeDefaults = true }

    fun encode(document: BackupDocument): ByteArray {
        val out = ByteArrayOutputStream()
        GZIPOutputStream(out).use { it.write(json.encodeToString(BackupDocument.serializer(), document).toByteArray(Charsets.UTF_8)) }
        return out.toByteArray()
    }

    fun decode(data: ByteArray): BackupDocument {
        val text = when {
            data.size >= 2 && data[0] == 0x1F.toByte() && data[1] == 0x8B.toByte() -> String(gunzip(data), Charsets.UTF_8)
            firstVisible(data) == '{'.code.toByte() -> String(data, Charsets.UTF_8)
            else -> throw BackupException.NotBackup
        }
        val header = runCatching { json.parseToJsonElement(text) as JsonObject }.getOrNull() ?: throw BackupException.Damaged
        val format = runCatching { header["format"]?.jsonPrimitive?.content }.getOrNull()
        val schema = runCatching { header["schema"]?.jsonPrimitive?.intOrNull }.getOrNull()
        if (format != BackupDocument.FORMAT || schema == null) throw BackupException.NotBackup
        if (schema > BackupDocument.SCHEMA) throw BackupException.NewerVersion
        return runCatching { json.decodeFromJsonElement(BackupDocument.serializer(), header) }.getOrNull() ?: throw BackupException.Damaged
    }

    private fun firstVisible(data: ByteArray): Byte? =
        data.firstOrNull { it !in listOf(0x20, 0x09, 0x0A, 0x0D, 0xEF, 0xBB, 0xBF).map(Int::toByte) }

    private fun gunzip(data: ByteArray): ByteArray = try {
        GZIPInputStream(ByteArrayInputStream(data)).use { input ->
            val out = ByteArrayOutputStream()
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                out.write(buffer, 0, read)
                if (out.size() > MAXIMUM_SIZE) throw BackupException.Damaged
            }
            out.toByteArray()
        }
    } catch (e: BackupException) {
        throw e
    } catch (e: Exception) {
        throw BackupException.Damaged
    }
}

/** What a backup would bring, for the review before restoring. */
data class BackupPreview(
    val created: Instant?,
    val platform: String?,
    val routes: Int,
    val checkIns: Int,
    /** Routes whose flight is on this phone already. None means the flights belong to another account or have not come back yet. */
    val routesWithFlightHere: Int,
)

/** What restoring did. */
data class BackupResult(val routes: Int = 0, val checkIns: Int = 0, val skipped: Int = 0)

/** Makes a backup of this phone and restores one into it. Restore only adds (docs/BACKUP-PLAN.md, decision 6). */
class BackupService(private val store: CheckInStore, private val tracks: FlightTrackFiles) {
    /** The routes on this phone and the check-ins the server does not have. */
    suspend fun make(app: String, now: Instant = Instant.now()): BackupDocument {
        val all = store.all()
        val byId = all.associateBy { it.id }
        val features = tracks.ids().sortedBy { it.toString() }.mapNotNull { id ->
            val points = tracks.load(id)?.takeIf { it.size >= 2 } ?: return@mapNotNull null
            val flight = byId[id]
            BackupDocument.Feature(
                properties = BackupDocument.Properties(
                    checkinId = id.toString(), flightNumber = flight?.flightNumber, origin = flight?.originCode,
                    destination = flight?.destinationCode, day = flight?.let { BackupDates.day(it.occurredAt) },
                ),
                geometry = BackupDocument.Geometry(coordinates = points.map { listOf(round5(it.longitude), round5(it.latitude)) }),
            )
        }
        val checkIns = all.filter { it.syncState != SyncState.SYNCED }.sortedBy { it.occurredAt }.map(::backupCheckIn)
        return BackupDocument(
            format = BackupDocument.FORMAT, schema = BackupDocument.SCHEMA, createdAt = BackupDates.format(now), app = app,
            platform = "android", counts = BackupDocument.Counts(features.size, checkIns.size),
            routes = BackupDocument.Routes(features = features), checkins = checkIns,
        )
    }

    suspend fun preview(document: BackupDocument): BackupPreview {
        val here = store.all().map { it.id }.toSet()
        val routeIds = document.routes.features.mapNotNull { uuid(it.properties.checkinId) }
        return BackupPreview(
            document.created, document.platform, routeIds.size, document.checkins.size, routeIds.count { it in here },
        )
    }

    suspend fun restore(document: BackupDocument, replaceRoutes: Boolean): BackupResult {
        var skipped = 0
        val usable = document.checkins.mapNotNull { localCheckIn(it) ?: null.also { skipped++ } }
        val added = store.restoreFromBackup(usable)
        skipped += usable.size - added.size
        var routes = 0
        for (feature in document.routes.features) {
            val id = uuid(feature.properties.checkinId)
            val points = points(feature.geometry)
            if (id == null || points == null || (tracks.has(id) && !replaceRoutes)) { skipped++; continue }
            tracks.save(points, id)
            routes++
        }
        return BackupResult(routes, added.size, skipped)
    }

    private fun round5(value: Double): Double = (value * 100_000).roundToLong() / 100_000.0

    companion object {
        private val kinds = setOf("spotted", "airport", "flown")

        private fun uuid(text: String?): UUID? = text?.let { runCatching { UUID.fromString(it) }.getOrNull() }

        private fun points(geometry: BackupDocument.Geometry): List<GeoCoordinate>? {
            if (geometry.type != "LineString" || geometry.coordinates.size < 2) return null
            return geometry.coordinates.map { pair ->
                if (pair.size < 2 || pair[0] !in -180.0..180.0 || pair[1] !in -90.0..90.0) return null
                GeoCoordinate(pair[1], pair[0])
            }
        }

        fun backupCheckIn(c: LocalCheckIn) = BackupCheckIn(
            id = c.id.toString(), kind = c.kind, occurredAt = BackupDates.format(c.occurredAt),
            timeKnown = if (c.timeKnown) null else false, savedAt = c.savedAt?.let(BackupDates::format),
            registration = c.registration, typeIcao = c.typeIcao, airportId = c.airportId, airportCode = c.airportCode,
            latitude = c.latitude, longitude = c.longitude, visitContext = c.visitContext, spotId = c.spotId, spotName = c.spotName,
            visitId = c.visitId?.toString(), originId = c.originId, originCode = c.originCode, destinationId = c.destinationId,
            destinationCode = c.destinationCode, flightNumber = c.flightNumber, cabin = c.cabin, seat = c.seat,
            flightId = c.flightId?.toString(), sourceId = c.sourceId?.toString(),
        )

        /** A pending check-in, so it goes to the account that is signed in or signs in next. Null when it cannot be used. */
        fun localCheckIn(b: BackupCheckIn): LocalCheckIn? {
            val id = uuid(b.id) ?: return null
            val occurredAt = BackupDates.parse(b.occurredAt) ?: return null
            if (b.kind !in kinds) return null
            if (b.latitude != null && b.latitude !in -90.0..90.0) return null
            if (b.longitude != null && b.longitude !in -180.0..180.0) return null
            return LocalCheckIn(
                id = id, kind = b.kind, occurredAt = occurredAt, registration = b.registration, typeIcao = b.typeIcao,
                airportId = b.airportId, latitude = b.latitude, longitude = b.longitude, syncState = SyncState.PENDING, rejectCode = null,
                airportCode = b.airportCode, originId = b.originId, destinationId = b.destinationId, originCode = b.originCode,
                destinationCode = b.destinationCode, flightNumber = b.flightNumber, cabin = b.cabin, seat = b.seat,
                visitContext = b.visitContext, flightId = uuid(b.flightId), sourceId = uuid(b.sourceId), spotId = b.spotId,
                spotName = b.spotName, visitId = uuid(b.visitId), savedAt = b.savedAt?.let(BackupDates::parse),
                timeKnown = b.timeKnown != false,
            )
        }
    }
}
