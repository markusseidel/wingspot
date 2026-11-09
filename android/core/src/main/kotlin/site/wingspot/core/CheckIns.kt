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
) {
    val hasAircraft: Boolean get() = registration != null || typeIcao != null
}

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
)

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
                """INSERT INTO checkins (id, kind, occurred_at, registration, type_icao, airport_id, latitude, longitude, sync_state)
                   VALUES (?, 'spotted', ?, ?, ?, ?, ?, ?, 'pending')""",
            ).use {
                it.bindText(1, id.toString())
                it.bindLong(2, now.toEpochMilli())
                draft.registration?.let { r -> it.bindText(3, r.value) } ?: it.bindNull(3)
                draft.typeIcao?.let { t -> it.bindText(4, t.uppercase()) } ?: it.bindNull(4)
                draft.airportId?.let { a -> it.bindLong(5, a) } ?: it.bindNull(5)
                draft.latitude?.let { v -> it.bindDouble(6, v) } ?: it.bindNull(6)
                draft.longitude?.let { v -> it.bindDouble(7, v) } ?: it.bindNull(7)
                it.step()
            }
            SpottedResult(id, subject, if (before == null) History.FirstTime else History.SeenBefore(before.first + 1, before.second))
        }
    }

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

    suspend fun markSynced(ids: Collection<UUID>) = setState(ids, "synced", null)

    suspend fun markRejected(id: UUID, code: String?) = setState(listOf(id), "rejected", code)

    private suspend fun setState(ids: Collection<UUID>, state: String, code: String?) = db {
        for (id in ids) {
            connection.prepare("UPDATE checkins SET sync_state = ?, reject_code = ? WHERE id = ?").use {
                it.bindText(1, state)
                code?.let { c -> it.bindText(2, c) } ?: it.bindNull(2)
                it.bindText(3, id.toString())
                it.step()
            }
        }
    }

    private suspend fun select(tail: String): List<LocalCheckIn> = db {
        connection.prepare(
            "SELECT id, kind, occurred_at, registration, type_icao, airport_id, latitude, longitude, sync_state, reject_code FROM checkins $tail",
        ).use { s ->
            buildList {
                while (s.step()) {
                    add(
                        LocalCheckIn(
                            UUID.fromString(s.getText(0)), s.getText(1), Instant.ofEpochMilli(s.getLong(2)),
                            s.text(3), s.text(4), s.long(5), s.double(6), s.double(7),
                            SyncState.valueOf(s.getText(8).uppercase()), s.text(9),
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
            connection.execSQL("CREATE INDEX IF NOT EXISTS checkins_pending ON checkins (sync_state, occurred_at)")
            return CheckInStore(connection)
        }
    }
}
