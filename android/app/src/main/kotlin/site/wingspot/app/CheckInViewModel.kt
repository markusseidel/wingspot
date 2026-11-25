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

/** One flight of a KML batch, ready to save. */
class BatchFlight(
    val origin: Airport, val destination: Airport, val flightNumber: String?, val registration: Registration?, val type: AircraftType?,
    val at: Instant, val track: List<site.wingspot.core.GeoCoordinate>,
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
    /** A KML file shared or opened into the app, for the flight form to read (#236). It is cleared once taken. */
    val incomingKml: android.net.Uri? = null,
    /** Several KML files picked or shared at once: the list that adds them all replaces the form (#236). */
    val kmlFiles: List<android.net.Uri> = emptyList(),
    /** The question when a friend's flight is one you already have ("Keep mine" or "Replace the flight data", #273). */
    val companionAsk: CompanionAsk? = null,
    /** A request that was just answered, so the inbox can drop it. */
    val companionAnswered: String? = null,
    val companionFailed: Boolean = false,
)

/** A friend's flight that you are about to take over, and the flight of yours that looks like the same one. */
data class CompanionAsk(val item: site.wingspot.core.FeedItem, val match: SocialApi.MatchingFlight)

/** Saves check-ins on the phone first, then asks for an upload. Works fully offline. */
class CheckInViewModel(
    private val store: CheckInStore,
    private val outbox: Outbox,
    private val requestUpload: () -> Unit,
    private val loadSession: () -> SpotSession? = { null },
    private val storeSession: (SpotSession?) -> Unit = {},
    /** Where the tracks of imported flights are kept on this phone. */
    private val tracks: site.wingspot.core.FlightTrackFiles? = null,
    private val social: SocialApi? = null,
) : ViewModel() {
    private val mutable = MutableStateFlow(CheckInState(session = loadSession()?.takeIf { it.isActive(Instant.now()) }))
    val state: StateFlow<CheckInState> = mutable.asStateFlow()

    init {
        reload()
    }

    fun open() {
        mutable.value = mutable.value.copy(isOpen = true, result = null, saveFailed = false, returnStart = null)
    }

    /** A KML file came in from another app: opens the flight form, which reads it. */
    fun openKmlFile(uri: android.net.Uri) {
        mutable.value = mutable.value.copy(isOpen = true, kind = Kind.FLOWN, result = null, editing = null, saveFailed = false, returnStart = null, afterFlight = null, incomingKml = uri)
    }

    /** Several KML files came in or were picked: opens the list that adds them all. */
    fun openKmlFiles(uris: List<android.net.Uri>) {
        mutable.value = mutable.value.copy(isOpen = true, kind = Kind.FLOWN, result = null, editing = null, saveFailed = false, returnStart = null, afterFlight = null, kmlFiles = uris)
    }

    fun closeKmlFiles() {
        mutable.value = mutable.value.copy(kmlFiles = emptyList())
    }

    /** Saves the ticked flights of a batch, each with its route (which stays on this phone), one after the other. [onDone] gets how many were saved. */
    fun saveKmlBatch(flights: List<BatchFlight>, onDone: (Int) -> Unit) {
        viewModelScope.launch {
            var saved = 0
            for (f in flights) {
                try {
                    val result = store.saveFlown(
                        FlownDraft(Place(f.origin.id, f.origin.code), Place(f.destination.id, f.destination.code), f.flightNumber.orEmpty(), f.registration, f.type?.icaoCode, null, "", emptyList()),
                        f.at,
                    )
                    if (f.track.size >= 2) runCatching { tracks?.save(f.track, result.id) }
                    saved++
                } catch (e: Exception) {
                    mutable.value = mutable.value.copy(saveFailed = true)
                }
            }
            requestUpload()
            reload()
            onDone(saved)
        }
    }

    /** The flight form took the file. */
    fun kmlTaken() {
        mutable.value = mutable.value.copy(incomingKml = null)
    }

    /** Opens the form of one kind straight away, for a shortcut of the app icon (#349). The running session is joined by the form itself. */
    fun openKind(kind: Kind) {
        mutable.value = mutable.value.copy(isOpen = true, kind = kind, result = null, editing = null, saveFailed = false, returnStart = null, afterFlight = null)
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

    /** [moment] is when it happened: now, or the day (and time) the person chose (#312). */
    fun save(
        registration: Registration?, type: AircraftType?, airport: Airport?, photos: List<PreparedPhoto>, spot: SocialApi.SpotLocation? = null,
        moment: site.wingspot.core.Moment = site.wingspot.core.Moment(Instant.now(), true),
    ) {
        val session = activeSession()
        val draft = SpottedDraft(
            registration, type?.icaoCode, airport?.id ?: session?.airportId, airportCode = airport?.code ?: session?.code,
            visitId = session?.visitId, spotId = if (session == null) spot?.id else null, spotName = if (session == null) spot?.name else null,
        )
        if (!draft.hasAircraft) return
        run(photos) {
            val result = store.saveSpotted(draft, moment.at, timeKnown = moment.timeKnown)
            result.id to SavedResult(
                Kind.SPOTTED, result.subject,
                (result.history as? History.SeenBefore)?.count ?: 1, (result.history as? History.SeenBefore)?.lastSeen,
            )
        }
    }

    fun saveAirport(
        airport: Airport, context: VisitContext, photos: List<PreparedPhoto>, tagged: List<UUID> = emptyList(), spot: SocialApi.SpotLocation? = null,
        moment: site.wingspot.core.Moment? = null,
    ) = run(photos) {
        val result = store.saveAirport(
            AirportDraft(Place(airport.id, airport.code), context, tagged = tagged, spotId = spot?.id, spotName = spot?.name),
            moment?.at ?: Instant.now(), timeKnown = moment?.timeKnown ?: true,
        )
        // A visit at a spotting location starts a session: the aircraft spotted next are linked to this visit.
        if (spot != null) {
            val session = SpotSession(result.id, spot.id, spot.name, airport.id, airport.code, Instant.now(), moment?.at, moment?.timeKnown ?: true)
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

    /**
     * "Add to my logbook" on a friend's flight or visit (#273). When a flight of yours looks like the same flight, the person is asked first
     * ([CheckInState.companionAsk]); otherwise a copy is saved, linked to the original.
     */
    fun acceptFromFriend(item: site.wingspot.core.FeedItem) {
        viewModelScope.launch {
            if (item.kind == "flown") {
                val asked = runCatching { social?.matchingFlights(item.id) }.getOrNull().orEmpty()
                val best = asked.firstOrNull() ?: localMatches(item).firstOrNull()
                if (best != null) {
                    mutable.value = mutable.value.copy(companionAsk = CompanionAsk(item, best))
                    return@launch
                }
            }
            addFromFriend(item)
        }
    }

    /** The flights on this phone with the same flight number on the same day, for when the server can't be asked. */
    private fun localMatches(item: site.wingspot.core.FeedItem): List<SocialApi.MatchingFlight> {
        val number = site.wingspot.core.KmlBatch.normalized(item.flightNumber)
        val day = runCatching { java.time.OffsetDateTime.parse(item.occurredAt).toInstant().atZone(java.time.ZoneId.systemDefault()).toLocalDate() }.getOrNull()
        if (number.isEmpty() || day == null) return emptyList()
        return mutable.value.all.filter {
            it.kind == "flown" && it.sourceId == null && site.wingspot.core.KmlBatch.normalized(it.flightNumber) == number &&
                it.occurredAt.atZone(java.time.ZoneId.systemDefault()).toLocalDate() == day
        }.map { SocialApi.MatchingFlight(it.id.toString(), "number", 0, it.flightNumber, it.occurredAt.toString(), it.originCode, it.destinationCode) }
    }

    fun dismissCompanionAsk() {
        mutable.value = mutable.value.copy(companionAsk = null, companionFailed = false)
    }

    /** The person chose what to do with the flight they already have. "Keep mine" links the two; "Replace" takes the friend's flight data over. */
    fun chooseCompanion(keepMine: Boolean) {
        val ask = mutable.value.companionAsk ?: return
        mutable.value = mutable.value.copy(companionAsk = null)
        viewModelScope.launch {
            try {
                val api = social ?: throw IllegalStateException("no connection")
                val mine = UUID.fromString(ask.match.id)
                val source = UUID.fromString(ask.item.id)
                if (keepMine) {
                    if (!api.linkCompanion(ask.match.id, ask.item.id)) throw IllegalStateException("refused")
                    store.setSource(mine, source)
                } else {
                    val facts = api.replaceFlightData(ask.match.id, ask.item.id) ?: throw IllegalStateException("refused")
                    val at = java.time.OffsetDateTime.parse(facts.occurredAt).toInstant()
                    store.replaceFlightData(
                        mine, facts.flightNumber, Place(facts.originId, ask.item.originCode ?: "?"), Place(facts.destinationId, ask.item.destinationCode ?: "?"),
                        at, facts.registration, facts.typeIcao, source,
                    )
                }
                mutable.value = mutable.value.copy(companionAnswered = ask.item.id)
                reload()
            } catch (e: Exception) {
                mutable.value = mutable.value.copy(companionFailed = true)
            }
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
                mutable.value = mutable.value.copy(companionAnswered = item.id)
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
    fun saveSimpleEdit(id: UUID, registration: Registration?, typeIcao: String?, reason: VisitContext?, photos: List<PreparedPhoto> = emptyList(), tagged: List<UUID>? = null, spot: SpotChange = SpotChange.Keep, moment: site.wingspot.core.Moment? = null) {
        viewModelScope.launch {
            try {
                if (reason != null) store.updateVisit(id, reason, tagged, moment?.at, moment?.timeKnown)
                else store.updateSpotted(id, registration, typeIcao, spot, moment?.at, moment?.timeKnown)
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
                    tracks = app.tracks, social = app.social,
                )
            }
        }
    }
}
