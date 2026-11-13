package site.wingspot.core

import androidx.sqlite.SQLiteConnection
import androidx.sqlite.SQLiteStatement
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.execSQL
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/** What the person entered for a spotted check-in. It needs a registration or a type. */
data class SpottedDraft(
    val registration: Registration? = null,
    val typeIcao: String? = null,
    val airportId: Long? = null,
    val latitude: Double? = null,
    val longitude: Double? = null,
    val airportCode: String? = null,
) {
    val hasAircraft: Boolean get() = registration != null || typeIcao != null
}

/** Why someone is at an airport. The names are what the server stores, in lower case. */
enum class VisitContext { SPOTTING, DEPARTING, ARRIVING, TRANSIT, WORKING, MUSEUM;
    val wire: String get() = name.lowercase()
}

/** An airport as a check-in keeps it: the id for the server and the code to show offline. */
data class Place(val airportId: Long, val code: String)

/** What the person entered for an airport visit. */
data class AirportDraft(
    val place: Place,
    val context: VisitContext = VisitContext.SPOTTING,
    val latitude: Double? = null,
    val longitude: Double? = null,
)

/** The cabin classes the server knows. */
enum class CabinClass { ECONOMY, PREMIUM_ECONOMY, BUSINESS, FIRST;
    val wire: String get() = name.lowercase()

    companion object {
        fun fromWire(value: String?): CabinClass? = entries.firstOrNull { it.wire == value }
    }
}

/** What the person entered for a flight. The date of the flight is [Instant] `now` at save time unless given. */
data class FlownDraft(
    val origin: Place,
    val destination: Place,
    val flightNumber: String? = null,
    val registration: Registration? = null,
    val typeIcao: String? = null,
    val cabin: CabinClass? = null,
    val seat: String? = null,
)

data class FlownResult(val id: UUID, val route: String, val timesOnRoute: Int)

data class AirportResult(val id: UUID, val code: String, val visitsHere: Int)

enum class SyncState { PENDING, SYNCED, REJECTED }

/** A check-in on this phone. [syncState] says whether the server has it. */
data class LocalCheckIn(
    val id: UUID,
    val kind: String,
    val occurredAt: Instant,
    val registration: String?,
    val typeIcao: String?,
    val airportId: Long?,
    val latitude: Double?,
    val longitude: Double?,
    val syncState: SyncState,
    val rejectCode: String?,
    val airportCode: String? = null,
    val originId: Long? = null,
    val destinationId: Long? = null,
    val originCode: String? = null,
    val destinationCode: String? = null,
    val flightNumber: String? = null,
    val cabin: String? = null,
    val seat: String? = null,
    val visitContext: String? = null,
) {
    /** What to show as the title: the registration, the route or the airport. */
    val title: String
        get() = when (kind) {
            "flown" -> "${originCode ?: "?"} → ${destinationCode ?: "?"}"
            "airport" -> airportCode ?: "?"
            else -> registration ?: typeIcao ?: "?"
        }
}

/** A photo waiting on the phone to go up with its check-in. The JPEG has no metadata. */
data class LocalPhoto(val id: UUID, val checkInId: UUID, val jpeg: ByteArray, val width: Int, val height: Int)

/** How often this aircraft has been seen, counting the check-in just saved. */
sealed class History {
    object FirstTime : History()
    data class SeenBefore(val count: Int, val lastSeen: Instant) : History()
}

data class SpottedResult(val id: UUID, val subject: String, val history: History)

/**
 * The check-ins on the phone and the outbox in one small database: every check-in is saved here first, so the app
 * works offline, and the rows that are still [SyncState.PENDING] are what gets uploaded.
 * [path] may be ":memory:" in tests.
 */
class CheckInStore private constructor(private val connection: SQLiteConnection) {
    private val lock = Mutex()

    /**
     * Saves a spotted check-in. Throws [IllegalArgumentException] without an aircraft. The registration is already
     * in its canonical form, because [Registration] only exists for valid input.
     */
    suspend fun saveSpotted(draft: SpottedDraft, now: Instant = Instant.now(), id: UUID = Uuid7.generate(now.toEpochMilli())): SpottedResult {
        require(draft.hasAircraft) { "A check-in needs a registration or a type." }
        require((draft.latitude == null) == (draft.longitude == null)) { "Latitude and longitude go together." }
        return db {
            val subject = draft.registration?.value ?: draft.typeIcao!!
            val before = timesSeen(subject)
            connection.prepare(
                """INSERT INTO checkins (id, kind, occurred_at, registration, type_icao, airport_id, latitude, longitude, sync_state, airport_code)
                   VALUES (?, 'spotted', ?, ?, ?, ?, ?, ?, 'pending', ?)""",
            ).use {
                it.bindText(1, id.toString())
                it.bindLong(2, now.toEpochMilli())
                draft.registration?.let { r -> it.bindText(3, r.value) } ?: it.bindNull(3)
                draft.typeIcao?.let { t -> it.bindText(4, t.uppercase()) } ?: it.bindNull(4)
                draft.airportId?.let { a -> it.bindLong(5, a) } ?: it.bindNull(5)
                draft.latitude?.let { v -> it.bindDouble(6, v) } ?: it.bindNull(6)
                draft.longitude?.let { v -> it.bindDouble(7, v) } ?: it.bindNull(7)
                draft.airportCode?.let { v -> it.bindText(8, v) } ?: it.bindNull(8)
                it.step()
            }
            SpottedResult(id, subject, if (before == null) History.FirstTime else History.SeenBefore(before.first + 1, before.second))
        }
    }


    /** Saves an airport visit and says how often this airport was visited, counting this one. */
    suspend fun saveAirport(draft: AirportDraft, now: Instant = Instant.now(), id: UUID = Uuid7.generate(now.toEpochMilli())): AirportResult {
        require((draft.latitude == null) == (draft.longitude == null)) { "Latitude and longitude go together." }
        return db {
            insertAirport(id, draft.place, draft.context, now, draft.latitude, draft.longitude)
            AirportResult(id, draft.place.code, count("kind = 'airport' AND airport_id = ?") { it.bindLong(1, draft.place.airportId) })
        }
    }

    private fun insertAirport(id: UUID, place: Place, context: VisitContext, at: Instant, latitude: Double?, longitude: Double?) {
        connection.prepare(
            """INSERT INTO checkins (id, kind, occurred_at, airport_id, airport_code, visit_context, latitude, longitude, sync_state)
               VALUES (?, 'airport', ?, ?, ?, ?, ?, ?, 'pending')""",
        ).use {
            it.bindText(1, id.toString()); it.bindLong(2, at.toEpochMilli())
            it.bindLong(3, place.airportId); it.bindText(4, place.code); it.bindText(5, context.wire)
            latitude?.let { v -> it.bindDouble(6, v) } ?: it.bindNull(6)
            longitude?.let { v -> it.bindDouble(7, v) } ?: it.bindNull(7)
            it.step()
        }
    }

    /**
     * Saves a flight, plus an airport visit for each end of it, so the airports count as visited. [at] is the day of
     * the flight. Throws [IllegalArgumentException] when both ends are the same airport.
     */
    suspend fun saveFlown(draft: FlownDraft, at: Instant = Instant.now(), id: UUID = Uuid7.generate(at.toEpochMilli())): FlownResult {
        require(draft.origin.airportId != draft.destination.airportId) { "A flight needs two different airports." }
        return db {
            val earlier = count("kind = 'flown' AND origin_id = ? AND destination_id = ?") {
                it.bindLong(1, draft.origin.airportId); it.bindLong(2, draft.destination.airportId)
            }
            val number = draft.flightNumber?.filterNot { it.isWhitespace() }?.uppercase()?.ifEmpty { null }
            val seat = draft.seat?.trim()?.uppercase()?.ifEmpty { null }
            connection.prepare(
                """INSERT INTO checkins (id, kind, occurred_at, registration, type_icao, origin_id, destination_id, origin_code,
                                         destination_code, flight_number, cabin, seat, sync_state)
                   VALUES (?, 'flown', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending')""",
            ).use {
                it.bindText(1, id.toString()); it.bindLong(2, at.toEpochMilli())
                draft.registration?.let { r -> it.bindText(3, r.value) } ?: it.bindNull(3)
                draft.typeIcao?.let { t -> it.bindText(4, t.uppercase()) } ?: it.bindNull(4)
                it.bindLong(5, draft.origin.airportId); it.bindLong(6, draft.destination.airportId)
                it.bindText(7, draft.origin.code); it.bindText(8, draft.destination.code)
                number?.let { v -> it.bindText(9, v) } ?: it.bindNull(9)
                draft.cabin?.let { v -> it.bindText(10, v.wire) } ?: it.bindNull(10)
                seat?.let { v -> it.bindText(11, v) } ?: it.bindNull(11)
                it.step()
            }
            insertAirport(Uuid7.generate(at.toEpochMilli()), draft.origin, VisitContext.DEPARTING, at, null, null)
            insertAirport(Uuid7.generate(at.toEpochMilli()), draft.destination, VisitContext.ARRIVING, at, null, null)
            FlownResult(id, "${draft.origin.code} → ${draft.destination.code}", earlier + 1)
        }
    }

    /**
     * Corrects the details of a saved flight and sends them again. The route, the day and the photos stay as they were.
     * Returns false when this phone has no such flight.
     */
    suspend fun updateFlown(
        id: UUID, registration: Registration?, typeIcao: String?, flightNumber: String?, cabin: CabinClass?, seat: String?,
    ): Boolean = db {
        val number = flightNumber?.filterNot { it.isWhitespace() }?.uppercase()?.ifEmpty { null }
        val seatText = seat?.trim()?.uppercase()?.ifEmpty { null }
        var found = false
        connection.prepare("SELECT 1 FROM checkins WHERE id = ? AND kind = 'flown'").use {
            it.bindText(1, id.toString()); found = it.step()
        }
        if (!found) return@db false
        connection.prepare(
            """UPDATE checkins SET registration = ?, type_icao = ?, flight_number = ?, cabin = ?, seat = ?,
                   sync_state = 'pending', reject_code = NULL WHERE id = ?""",
        ).use {
            registration?.let { r -> it.bindText(1, r.value) } ?: it.bindNull(1)
            typeIcao?.let { t -> it.bindText(2, t.uppercase()) } ?: it.bindNull(2)
            number?.let { v -> it.bindText(3, v) } ?: it.bindNull(3)
            cabin?.let { v -> it.bindText(4, v.wire) } ?: it.bindNull(4)
            seatText?.let { v -> it.bindText(5, v) } ?: it.bindNull(5)
            it.bindText(6, id.toString())
            it.step()
        }
        true
    }

    /** Removes a check-in and its photos from this phone. Does nothing if there is none. */
    suspend fun delete(id: UUID) = db {
        for (sql in listOf("DELETE FROM photos WHERE checkin_id = ?", "DELETE FROM checkins WHERE id = ?")) {
            connection.prepare(sql).use { it.bindText(1, id.toString()); it.step() }
        }
    }

    /** One check-in by id, or null. */
    suspend fun find(id: UUID): LocalCheckIn? = select("WHERE id = '$id'").firstOrNull()

    /** True when the server may already have this check-in, so deleting it needs the server too. */
    suspend fun mayBeOnServer(id: UUID): Boolean = db {
        var answer = false
        connection.prepare("SELECT sync_state, synced_at FROM checkins WHERE id = ?").use {
            it.bindText(1, id.toString())
            if (it.step()) answer = it.getText(0) == "synced" || !it.isNull(1)
        }
        answer
    }

    // Photos ----------------------------------------------------------------------------------------------------------

    /** Keeps a photo with its check-in. Up to four go on one check-in; more are ignored. */
    suspend fun addPhoto(checkInId: UUID, jpeg: ByteArray, width: Int, height: Int, now: Instant = Instant.now()): UUID? = db {
        if (count("checkin_id = ?", table = "photos") { it.bindText(1, checkInId.toString()) } >= MAX_PHOTOS) return@db null
        val id = Uuid7.generate(now.toEpochMilli())
        connection.prepare(
            "INSERT INTO photos (id, checkin_id, jpeg, width, height, created_at, sync_state) VALUES (?, ?, ?, ?, ?, ?, 'pending')",
        ).use {
            it.bindText(1, id.toString()); it.bindText(2, checkInId.toString()); it.bindBlob(3, jpeg)
            it.bindLong(4, width.toLong()); it.bindLong(5, height.toLong()); it.bindLong(6, now.toEpochMilli())
            it.step()
        }
        id
    }

    /** Pending photos whose check-in the server already has, oldest first. A photo of a rejected check-in is rejected too. */
    suspend fun photosReadyToSend(): List<LocalPhoto> = db {
        connection.prepare(
            """UPDATE photos SET sync_state = 'rejected', reject_code = 'checkin_rejected'
               WHERE sync_state = 'pending' AND checkin_id IN (SELECT id FROM checkins WHERE sync_state = 'rejected')""",
        ).use { it.step() }
        connection.prepare(
            """SELECT p.id, p.checkin_id, p.jpeg, p.width, p.height FROM photos p
               JOIN checkins c ON c.id = p.checkin_id
               WHERE p.sync_state = 'pending' AND c.sync_state = 'synced' ORDER BY p.created_at ASC""",
        ).use { s ->
            buildList {
                while (s.step()) add(LocalPhoto(UUID.fromString(s.getText(0)), UUID.fromString(s.getText(1)), s.getBlob(2), s.getLong(3).toInt(), s.getLong(4).toInt()))
            }
        }
    }

    suspend fun markPhoto(id: UUID, state: SyncState, code: String? = null) = db {
        connection.prepare("UPDATE photos SET sync_state = ?, reject_code = ? WHERE id = ?").use {
            it.bindText(1, state.name.lowercase())
            code?.let { c -> it.bindText(2, c) } ?: it.bindNull(2)
            it.bindText(3, id.toString())
            it.step()
        }
    }

    /** How many photos this check-in has on this phone. */
    suspend fun photoCount(checkInId: UUID): Int = db { count("checkin_id = ?", table = "photos") { it.bindText(1, checkInId.toString()) } }

    private fun count(where: String, table: String = "checkins", bind: (SQLiteStatement) -> Unit): Int =
        connection.prepare("SELECT COUNT(*) FROM $table WHERE $where").use { bind(it); it.step(); it.getLong(0).toInt() }

    /** (count, last time) of earlier spotted check-ins of this registration or type, or null. */
    private fun timesSeen(subject: String): Pair<Int, Instant>? =
        connection.prepare(
            "SELECT COUNT(*), MAX(occurred_at) FROM checkins WHERE kind = 'spotted' AND (registration = ? OR (registration IS NULL AND type_icao = ?))",
        ).use {
            it.bindText(1, subject); it.bindText(2, subject)
            it.step()
            val count = it.getLong(0).toInt()
            if (count == 0) null else count to Instant.ofEpochMilli(it.getLong(1))
        }

    /** Newest first. */
    suspend fun recent(limit: Int = 50): List<LocalCheckIn> = select("ORDER BY occurred_at DESC, id DESC LIMIT $limit")

    /** The oldest not yet uploaded, in the order they were made. */
    suspend fun pending(limit: Int = 50): List<LocalCheckIn> =
        select("WHERE sync_state = 'pending' ORDER BY occurred_at ASC, id ASC LIMIT $limit")

    suspend fun markSynced(ids: Collection<UUID>) = setState(ids, "synced", null, syncedAt = System.currentTimeMillis())

    suspend fun markRejected(id: UUID, code: String?) = setState(listOf(id), "rejected", code)

    private suspend fun setState(ids: Collection<UUID>, state: String, code: String?, syncedAt: Long? = null) = db {
        for (id in ids) {
            connection.prepare("UPDATE checkins SET sync_state = ?, reject_code = ?, synced_at = COALESCE(?, synced_at) WHERE id = ?").use {
                it.bindText(1, state)
                code?.let { c -> it.bindText(2, c) } ?: it.bindNull(2)
                syncedAt?.let { v -> it.bindLong(3, v) } ?: it.bindNull(3)
                it.bindText(4, id.toString())
                it.step()
            }
        }
    }

    private suspend fun select(tail: String): List<LocalCheckIn> = db {
        connection.prepare(
            """SELECT id, kind, occurred_at, registration, type_icao, airport_id, latitude, longitude, sync_state, reject_code,
                      airport_code, origin_id, destination_id, origin_code, destination_code, flight_number, cabin, seat, visit_context
               FROM checkins $tail""",
        ).use { s ->
            buildList {
                while (s.step()) {
                    add(
                        LocalCheckIn(
                            UUID.fromString(s.getText(0)), s.getText(1), Instant.ofEpochMilli(s.getLong(2)),
                            s.text(3), s.text(4), s.long(5), s.double(6), s.double(7),
                            SyncState.valueOf(s.getText(8).uppercase()), s.text(9),
                            s.text(10), s.long(11), s.long(12), s.text(13), s.text(14), s.text(15), s.text(16), s.text(17), s.text(18),
                        ),
                    )
                }
            }
        }
    }

    private fun SQLiteStatement.text(i: Int) = if (isNull(i)) null else getText(i)
    private fun SQLiteStatement.long(i: Int) = if (isNull(i)) null else getLong(i)
    private fun SQLiteStatement.double(i: Int) = if (isNull(i)) null else getDouble(i)

    private suspend fun <T> db(block: () -> T): T = withContext(Dispatchers.IO) { lock.withLock { block() } }

    fun close() = connection.close()

    companion object {
        /** The server takes at most four photos on one check-in. */
        const val MAX_PHOTOS = 4

        fun open(path: String): CheckInStore {
            val connection = BundledSQLiteDriver().open(path)
            connection.execSQL("PRAGMA journal_mode = WAL")
            connection.execSQL(
                """CREATE TABLE IF NOT EXISTS checkins (
                     id TEXT PRIMARY KEY,
                     kind TEXT NOT NULL,
                     occurred_at INTEGER NOT NULL,
                     registration TEXT,
                     type_icao TEXT,
                     airport_id INTEGER,
                     latitude REAL,
                     longitude REAL,
                     sync_state TEXT NOT NULL DEFAULT 'pending',
                     reject_code TEXT
                   )""",
            )
            // Columns added after the first release open an existing database without a migration step.
            val have = buildSet {
                connection.prepare("PRAGMA table_info(checkins)").use { while (it.step()) add(it.getText(1)) }
            }
            for ((name, type) in listOf(
                "airport_code" to "TEXT", "origin_id" to "INTEGER", "destination_id" to "INTEGER", "origin_code" to "TEXT",
                "destination_code" to "TEXT", "flight_number" to "TEXT", "cabin" to "TEXT", "seat" to "TEXT",
                "visit_context" to "TEXT", "synced_at" to "INTEGER",
            )) if (name !in have) connection.execSQL("ALTER TABLE checkins ADD COLUMN $name $type")
            connection.execSQL("CREATE INDEX IF NOT EXISTS checkins_pending ON checkins (sync_state, occurred_at)")
            connection.execSQL(
                """CREATE TABLE IF NOT EXISTS photos (
                     id TEXT PRIMARY KEY,
                     checkin_id TEXT NOT NULL,
                     jpeg BLOB NOT NULL,
                     width INTEGER NOT NULL,
                     height INTEGER NOT NULL,
                     created_at INTEGER NOT NULL,
                     sync_state TEXT NOT NULL DEFAULT 'pending',
                     reject_code TEXT
                   )""",
            )
            return CheckInStore(connection)
        }
    }
}
