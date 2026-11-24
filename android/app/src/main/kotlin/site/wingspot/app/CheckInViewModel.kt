package site.wingspot.app

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import site.wingspot.core.AircraftType
import site.wingspot.core.Airport
import site.wingspot.core.AirportDraft
import site.wingspot.core.CabinClass
import site.wingspot.core.CheckInStore
import site.wingspot.core.FlownDraft
import site.wingspot.core.History
import site.wingspot.core.LocalCheckIn
import site.wingspot.core.Outbox
import site.wingspot.core.Place
import site.wingspot.core.Registration
import site.wingspot.core.SocialApi
import site.wingspot.core.SpotChange
import site.wingspot.core.SpotSession
import site.wingspot.core.SpottedDraft
import site.wingspot.core.VisitContext

enum class Kind { SPOTTED, AIRPORT, FLOWN }

/** What the result page says after a save. [count] includes the check-in just saved; [lastSeen] is for spotted ones seen before. */
data class SavedResult(val kind: Kind, val title: String, val count: Int, val lastSeen: Instant?, val trackPositions: Int = 0)

/**
 * The first values of the flight form for a return flight: the route the other way round, the same day, and the cabin
 * and friends of the flight before. The flight number, aircraft and seat differ, so they stay empty.
 */
data class ReturnStart(
    val origin: Airport, val destination: Airport, val date: java.time.LocalDate, val cabin: CabinClass?,
    val tagged: List<site.wingspot.core.Person>,
)

data class CheckInState(
    val isOpen: Boolean = false,
    val kind: Kind = Kind.SPOTTED,
    val result: SavedResult? = null,
    val recent: List<LocalCheckIn> = emptyList(),
    /** Every check-in on this phone, for the profile numbers and collections. */
    val all: List<LocalCheckIn> = emptyList(),
    val saveFailed: Boolean = false,
    /** The flight being edited. */
    val editing: LocalCheckIn? = null,
    /** How many more photos the check-in being edited can take. */
    val roomForPhotos: Int = 0,
    val deleteFailed: Boolean = false,
    /** What the flight form starts with, when it was opened for a return flight. */
    val returnStart: ReturnStart? = null,
    /** The flight back for the flight just saved, offered on its result page. */
    val afterFlight: ReturnStart? = null,
    /** The running spotting session: aircraft spotted now are linked to its visit. */
    val session: SpotSession? = null,
)

/** Saves check-ins on the phone first, then asks for an upload. Works fully offline. */
class CheckInViewModel(
    private val store: CheckInStore,
    private val outbox: Outbox,
    private val requestUpload: () -> Unit,
    private val loadSession: () -> SpotSession? = { null },
    private val storeSession: (SpotSession?) -> Unit = {},
    /** Where the tracks of imported flights are kept on this phone. */
    private val tracks: site.wingspot.core.FlightTrackFiles? = null,
) : ViewModel() {
    private val mutable = MutableStateFlow(CheckInState(session = loadSession()?.takeIf { it.isActive(Instant.now()) }))
    val state: StateFlow<CheckInState> = mutable.asStateFlow()

    init {
        reload()
    }

    fun open() {
        mutable.value = mutable.value.copy(isOpen = true, result = null, saveFailed = false, returnStart = null)
    }

    /** Opens the flight form for a return flight, from the page of a flight or from the result of one. */
    fun startReturn(start: ReturnStart) {
        mutable.value = mutable.value.copy(isOpen = true, result = null, saveFailed = false, kind = Kind.FLOWN, returnStart = start)
    }

    /** From the result page: the flight back for the flight just saved. */
    fun returnFromResult() {
        mutable.value.afterFlight?.let(::startReturn)
    }

    fun close() {
        mutable.value = mutable.value.copy(isOpen = false, result = null, editing = null, returnStart = null, afterFlight = null)
    }

    fun chooseKind(kind: Kind) {
        mutable.value = mutable.value.copy(kind = kind, saveFailed = false)
    }

    /** Starts the next check-in. The form keeps its airport, because spotters log several planes in one place. */
    fun another() {
        mutable.value = mutable.value.copy(result = null, returnStart = null)
    }

    /** The running session, unless it ran out. */
    private fun activeSession(): SpotSession? = mutable.value.session?.takeIf { it.isActive(Instant.now()) }

    fun endSession() {
        storeSession(null)
        mutable.value = mutable.value.copy(session = null)
    }

    fun save(registration: Registration?, type: AircraftType?, airport: Airport?, photos: List<PreparedPhoto>, spot: SocialApi.SpotLocation? = null) {
        val session = activeSession()
        val draft = SpottedDraft(
            registration, type?.icaoCode, airport?.id ?: session?.airportId, airportCode = airport?.code ?: session?.code,
            visitId = session?.visitId, spotId = if (session == null) spot?.id else null, spotName = if (session == null) spot?.name else null,
        )
        if (!draft.hasAircraft) return
        run(photos) {
            val result = store.saveSpotted(draft)
            result.id to SavedResult(
                Kind.SPOTTED, result.subject,
                (result.history as? History.SeenBefore)?.count ?: 1, (result.history as? History.SeenBefore)?.lastSeen,
            )
        }
    }

    fun saveAirport(
        airport: Airport, context: VisitContext, photos: List<PreparedPhoto>, tagged: List<UUID> = emptyList(), spot: SocialApi.SpotLocation? = null,
    ) = run(photos) {
        val result = store.saveAirport(
            AirportDraft(Place(airport.id, airport.code), context, tagged = tagged, spotId = spot?.id, spotName = spot?.name),
        )
        // A visit at a spotting location starts a session: the aircraft spotted next are linked to this visit.
        if (spot != null) {
            val session = SpotSession(result.id, spot.id, spot.name, airport.id, airport.code, Instant.now())
            storeSession(session)
            mutable.value = mutable.value.copy(session = session)
        }
        result.id to SavedResult(Kind.AIRPORT, result.code, result.visitsHere, null)
    }

    fun saveFlight(
        origin: Airport, destination: Airport, flightNumber: String, registration: Registration?, type: AircraftType?,
        cabin: CabinClass?, seat: String, photos: List<PreparedPhoto>, at: Instant = Instant.now(), tagged: List<UUID> = emptyList(),
        returnTo: ReturnStart? = null, track: List<site.wingspot.core.GeoCoordinate> = emptyList(),
    ) = run(photos, onSaved = { it.copy(afterFlight = returnTo) }) {
        val result = store.saveFlown(
            FlownDraft(
                Place(origin.id, origin.code), Place(destination.id, destination.code), flightNumber, registration,
                type?.icaoCode, cabin, seat, tagged,
            ),
            at,
        )
        // The route of an imported flight stays on this phone and is never uploaded.
        val keepTrack = track.size >= 2 && runCatching { tracks?.save(track, result.id) }.isSuccess && tracks != null
        result.id to SavedResult(Kind.FLOWN, result.route, result.timesOnRoute, null, trackPositions = if (keepTrack) track.size else 0)
    }

    /** Keeps the photos with the check-in in the order given: each is one millisecond later than the one before, so they sort that way. */
    private suspend fun addPhotos(id: UUID, photos: List<PreparedPhoto>) {
        val start = Instant.now()
        photos.forEachIndexed { index, photo -> store.addPhoto(id, photo.jpeg, photo.width, photo.height, start.plusMillis(index.toLong())) }
    }

    private fun run(photos: List<PreparedPhoto>, onSaved: (CheckInState) -> CheckInState = { it }, save: suspend () -> Pair<UUID, SavedResult>) {
        viewModelScope.launch {
            try {
                val (id, result) = save()
                addPhotos(id, photos)
                mutable.value = onSaved(mutable.value.copy(result = result, saveFailed = false))
                requestUpload()
                reload()
            } catch (e: Exception) {
                mutable.value = mutable.value.copy(saveFailed = true)
            }
        }
    }

    fun edit(id: UUID) {
        viewModelScope.launch {
            val room = maxOf(0, CheckInStore.MAX_PHOTOS - store.photoCount(id))
            mutable.value = mutable.value.copy(editing = store.find(id), roomForPhotos = room, saveFailed = false)
        }
    }

    /** Adds a friend's flight or airport visit that you are tagged on to your own logbook, linked to the original. */
    fun addFromFriend(item: site.wingspot.core.FeedItem) {
        val at = runCatching { java.time.OffsetDateTime.parse(item.occurredAt).toInstant() }.getOrNull() ?: return
        val source = runCatching { UUID.fromString(item.id) }.getOrNull() ?: return
        viewModelScope.launch {
            try {
                if (item.kind == "flown" && item.originId != null && item.destinationId != null) {
                    store.saveFlown(
                        FlownDraft(
                            Place(item.originId!!, item.originCode ?: "?"), Place(item.destinationId!!, item.destinationCode ?: "?"),
                            item.flightNumber, item.registration?.let { Registration.parse(it) }, item.typeIcao, sourceId = source,
                        ),
                        at,
                    )
                } else if (item.kind == "airport" && item.airportId != null) {
                    store.saveAirport(AirportDraft(Place(item.airportId!!, item.airportCode ?: "?"), VisitContext.SPOTTING, sourceId = source), at)
                } else {
                    return@launch
                }
                requestUpload()
                reload()
            } catch (e: Exception) {
                mutable.value = mutable.value.copy(saveFailed = true)
            }
        }
    }

    fun cancelEdit() {
        mutable.value = mutable.value.copy(editing = null)
    }

    fun saveEdit(id: UUID, registration: Registration?, type: AircraftType?, typeIcao: String?, flightNumber: String, cabin: CabinClass?, seat: String, at: Instant? = null, photos: List<PreparedPhoto> = emptyList(), tagged: List<UUID>? = null) {
        viewModelScope.launch {
            try {
                store.updateFlown(id, registration, type?.icaoCode ?: typeIcao, flightNumber, cabin, seat, at, tagged)
                addPhotos(id, photos)
                mutable.value = mutable.value.copy(editing = null, saveFailed = false)
                requestUpload()
                reload()
            } catch (e: Exception) {
                mutable.value = mutable.value.copy(saveFailed = true)
            }
        }
    }

    /** Saves the corrected aircraft of a sighting, or the corrected reason of an airport visit. */
    fun saveSimpleEdit(id: UUID, registration: Registration?, typeIcao: String?, reason: VisitContext?, photos: List<PreparedPhoto> = emptyList(), tagged: List<UUID>? = null, spot: SpotChange = SpotChange.Keep) {
        viewModelScope.launch {
            try {
                if (reason != null) store.updateVisit(id, reason, tagged) else store.updateSpotted(id, registration, typeIcao, spot)
                addPhotos(id, photos)
                mutable.value = mutable.value.copy(editing = null, saveFailed = false)
                requestUpload()
                reload()
            } catch (e: Exception) {
                mutable.value = mutable.value.copy(saveFailed = true)
            }
        }
    }

    /** Deletes a check-in on the server and on the phone. If the server can't be reached it stays, and the page says so. */
    fun delete(id: UUID) {
        viewModelScope.launch {
            val removed = outbox.delete(id)
            mutable.value = mutable.value.copy(deleteFailed = !removed)
            reload()
        }
    }

    fun dismissDeleteFailed() {
        mutable.value = mutable.value.copy(deleteFailed = false)
    }

    /** Called after an upload may have changed the states. */
    fun reload() {
        viewModelScope.launch { val everything = store.all(); mutable.value = mutable.value.copy(recent = everything.take(200), all = everything) }
    }

    companion object {
        fun factory(app: WingspotApp): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                CheckInViewModel(
                    app.checkIns, app.outbox, { OutboxWorker.schedule(app) },
                    { SpotSession.decode(app.prefs.spotSession) }, { app.prefs.spotSession = it?.encode() },
                    tracks = app.tracks,
                )
            }
        }
    }
}
