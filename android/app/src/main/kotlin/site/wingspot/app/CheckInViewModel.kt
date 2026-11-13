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
import site.wingspot.core.SpottedDraft
import site.wingspot.core.VisitContext

enum class Kind { SPOTTED, AIRPORT, FLOWN }

/** What the result page says after a save. [count] includes the check-in just saved; [lastSeen] is for spotted ones seen before. */
data class SavedResult(val kind: Kind, val title: String, val count: Int, val lastSeen: Instant?)

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
    val deleteFailed: Boolean = false,
)

/** Saves check-ins on the phone first, then asks for an upload. Works fully offline. */
class CheckInViewModel(
    private val store: CheckInStore,
    private val outbox: Outbox,
    private val requestUpload: () -> Unit,
) : ViewModel() {
    private val mutable = MutableStateFlow(CheckInState())
    val state: StateFlow<CheckInState> = mutable.asStateFlow()

    init {
        reload()
    }

    fun open() {
        mutable.value = mutable.value.copy(isOpen = true, result = null, saveFailed = false)
    }

    fun close() {
        mutable.value = mutable.value.copy(isOpen = false, result = null, editing = null)
    }

    fun chooseKind(kind: Kind) {
        mutable.value = mutable.value.copy(kind = kind, saveFailed = false)
    }

    /** Starts the next check-in. The form keeps its airport, because spotters log several planes in one place. */
    fun another() {
        mutable.value = mutable.value.copy(result = null)
    }

    fun save(registration: Registration?, type: AircraftType?, airport: Airport?, photo: PreparedPhoto?) {
        val draft = SpottedDraft(registration, type?.icaoCode, airport?.id, airportCode = airport?.code)
        if (!draft.hasAircraft) return
        run(photo) {
            val result = store.saveSpotted(draft)
            result.id to SavedResult(
                Kind.SPOTTED, result.subject,
                (result.history as? History.SeenBefore)?.count ?: 1, (result.history as? History.SeenBefore)?.lastSeen,
            )
        }
    }

    fun saveAirport(airport: Airport, context: VisitContext, photo: PreparedPhoto?) = run(photo) {
        val result = store.saveAirport(AirportDraft(Place(airport.id, airport.code), context))
        result.id to SavedResult(Kind.AIRPORT, result.code, result.visitsHere, null)
    }

    fun saveFlight(
        origin: Airport, destination: Airport, flightNumber: String, registration: Registration?, type: AircraftType?,
        cabin: CabinClass?, seat: String, photo: PreparedPhoto?, at: Instant = Instant.now(),
    ) = run(photo) {
        val result = store.saveFlown(
            FlownDraft(
                Place(origin.id, origin.code), Place(destination.id, destination.code), flightNumber, registration,
                type?.icaoCode, cabin, seat,
            ),
            at,
        )
        result.id to SavedResult(Kind.FLOWN, result.route, result.timesOnRoute, null)
    }

    private fun run(photo: PreparedPhoto?, save: suspend () -> Pair<UUID, SavedResult>) {
        viewModelScope.launch {
            try {
                val (id, result) = save()
                if (photo != null) store.addPhoto(id, photo.jpeg, photo.width, photo.height)
                mutable.value = mutable.value.copy(result = result, saveFailed = false)
                requestUpload()
                reload()
            } catch (e: Exception) {
                mutable.value = mutable.value.copy(saveFailed = true)
            }
        }
    }

    fun edit(id: UUID) {
        viewModelScope.launch { mutable.value = mutable.value.copy(editing = store.find(id), saveFailed = false) }
    }

    fun cancelEdit() {
        mutable.value = mutable.value.copy(editing = null)
    }

    fun saveEdit(id: UUID, registration: Registration?, type: AircraftType?, typeIcao: String?, flightNumber: String, cabin: CabinClass?, seat: String) {
        viewModelScope.launch {
            try {
                store.updateFlown(id, registration, type?.icaoCode ?: typeIcao, flightNumber, cabin, seat)
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
            initializer { CheckInViewModel(app.checkIns, app.outbox) { OutboxWorker.schedule(app) } }
        }
    }
}
